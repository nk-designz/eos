defmodule Eos.K8s.PluginController do
  @moduledoc """
  Reconciles the desired state of a Plugin CRD against actual K8s Pods.

  - On add/modify: ensures the plugin token Secret exists, then ensures a Pod exists.
  - On delete: removes the Pod, the token Secret, and cancels the Phaeton subscription.
  """

  require Logger

  alias Eos.K8s.Client
  alias Eos.Plugins.Token

  def reconcile(plugin) do
    name = get_in(plugin, ["metadata", "name"])
    spec = plugin["spec"] || %{}
    replicas = Map.get(spec, "replicas", 1)

    if replicas == 0 do
      ensure_pod_deleted(name)
      patch_status(name, %{"phase" => "Stopped"})
    else
      with {:ok, _token} <- ensure_token_secret(name),
           {:ok, broker_config} <- resolve_broker_config(plugin) do
        ensure_pod_running(name, plugin, broker_config)
      else
        {:error, reason} ->
          Logger.error(
            "[PluginController] Could not reconcile plugin #{name}: #{inspect(reason)}"
          )

          patch_status(name, %{"phase" => "Error", "errorMessage" => inspect(reason)})
      end
    end
  end

  def cleanup(plugin) do
    name = get_in(plugin, ["metadata", "name"])
    sub_id = get_in(plugin, ["status", "subscriptionId"])
    broker_config = resolve_broker_config_silent(plugin)

    if sub_id do
      Eos.Broker.SubscriptionManager.delete(sub_id, broker_config)
    end

    ensure_pod_deleted(name)
    Client.delete_secret("eos-plugin-#{name}-token")
    Eos.Plugins.Registry.unregister(name)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp ensure_token_secret(plugin_name) do
    secret_name = "eos-plugin-#{plugin_name}-token"
    token = Token.generate(plugin_name)

    case Client.create_secret(secret_name, %{"PLUGIN_TOKEN" => token}) do
      {:ok, _} ->
        patch_status(plugin_name, %{"tokenSecret" => secret_name})

        Logger.info(
          "[PluginController] Created token secret #{secret_name} for plugin #{plugin_name}"
        )

        {:ok, token}

      {:error, %{"reason" => "AlreadyExists"}} ->
        # Secret already exists, token is deterministic
        {:ok, token}

      {:error, reason} ->
        Logger.warning(
          "[PluginController] Could not create token secret for #{plugin_name}: #{inspect(reason)}"
        )

        # Return the token anyway — verification still works via HMAC
        {:ok, token}
    end
  end

  defp resolve_broker_config(plugin) do
    broker_ref = get_in(plugin, ["spec", "brokerRef"])

    with {:broker_ref, ref} when is_binary(ref) <- {:broker_ref, broker_ref},
         {:ok, broker} <- Client.get_broker(ref),
         {:ok, token} <- read_broker_token(broker) do
      {:ok,
       %{
         url: get_in(broker, ["spec", "url"]),
         token: token,
         tenant: get_in(broker, ["spec", "tenant"])
       }}
    else
      {:broker_ref, _} -> {:error, "brokerRef not set or invalid in plugin spec"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_broker_config_silent(plugin) do
    case resolve_broker_config(plugin) do
      {:ok, config} -> config
      _ -> nil
    end
  end

  defp read_broker_token(broker) do
    secret_name = get_in(broker, ["spec", "tokenSecretRef", "name"])
    secret_key = get_in(broker, ["spec", "tokenSecretRef", "key"]) || "token"

    case Client.read_secret_value(secret_name, secret_key) do
      {:ok, nil} ->
        {:error, "broker token key '#{secret_key}' not found in secret '#{secret_name}'"}

      {:ok, token} ->
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_pod_running(plugin_name, plugin, broker_config) do
    pod_name = pod_name_for(plugin_name)

    case Client.get_pod(pod_name) do
      {:ok, _pod} ->
        :ok

      {:error, _} ->
        create_plugin_pod(plugin_name, plugin, broker_config)
    end
  end

  defp ensure_pod_deleted(plugin_name) do
    pod_name = pod_name_for(plugin_name)

    case Client.delete_pod(pod_name) do
      {:ok, _} ->
        :ok

      {:error, %{"reason" => "NotFound"}} ->
        :ok

      {:error, reason} ->
        Logger.warning("[PluginController] Could not delete pod #{pod_name}: #{inspect(reason)}")
    end
  end

  defp create_plugin_pod(plugin_name, plugin, broker_config) do
    spec = plugin["spec"] || %{}
    pod_name = pod_name_for(plugin_name)
    image = spec["image"]
    token_secret = "eos-plugin-#{plugin_name}-token"
    agent_ws_url = Application.get_env(:eos, :agent_ws_url, "ws://eos:4000/plugins")
    namespace = Client.namespace()

    manifest = %{
      "apiVersion" => "v1",
      "kind" => "Pod",
      "metadata" => %{
        "name" => pod_name,
        "namespace" => namespace,
        "labels" => %{
          "app.kubernetes.io/managed-by" => "eos",
          "eos.io/plugin" => plugin_name
        },
        "ownerReferences" => [
          %{
            "apiVersion" => "eos.io/v1alpha1",
            "kind" => "Plugin",
            "name" => plugin_name,
            "uid" => get_in(plugin, ["metadata", "uid"]),
            "blockOwnerDeletion" => true,
            "controller" => true
          }
        ]
      },
      "spec" => %{
        "restartPolicy" => "Always",
        "securityContext" => %{"runAsNonRoot" => true},
        "containers" => [
          %{
            "name" => "plugin",
            "image" => image,
            "env" => build_env(plugin_name, agent_ws_url, broker_config),
            "envFrom" => [%{"secretRef" => %{"name" => token_secret, "optional" => false}}],
            "resources" => build_resources(spec),
            "securityContext" => %{
              "allowPrivilegeEscalation" => false,
              "readOnlyRootFilesystem" => true
            }
          }
        ]
      }
    }

    case Client.create_pod(manifest) do
      {:ok, _pod} ->
        Logger.info("[PluginController] Created pod #{pod_name} for plugin #{plugin_name}")
        patch_status(plugin_name, %{"phase" => "Pending", "podName" => pod_name})

      {:error, reason} ->
        Logger.error(
          "[PluginController] Failed to create pod for #{plugin_name}: #{inspect(reason)}"
        )

        patch_status(plugin_name, %{"phase" => "Error", "errorMessage" => inspect(reason)})
    end
  end

  defp build_env(plugin_name, agent_ws_url, broker_config) do
    [
      %{"name" => "PLUGIN_ID", "value" => plugin_name},
      %{"name" => "IOT_AGENT_WS_URL", "value" => agent_ws_url},
      %{"name" => "BROKER_URL", "value" => broker_config[:url] || broker_config["url"] || ""},
      %{
        "name" => "BROKER_TENANT",
        "value" => broker_config[:tenant] || broker_config["tenant"] || ""
      }
    ]
  end

  defp build_resources(spec) do
    default = %{
      "requests" => %{"cpu" => "50m", "memory" => "64Mi"},
      "limits" => %{"cpu" => "500m", "memory" => "256Mi"}
    }

    Map.merge(default, spec["resources"] || %{})
  end

  defp patch_status(plugin_name, status) do
    case Client.patch_plugin_status(plugin_name, status) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[PluginController] Could not patch status for #{plugin_name}: #{inspect(reason)}"
        )
    end
  end

  defp pod_name_for(plugin_name), do: "eos-plugin-#{plugin_name}"
end
