defmodule EosWeb.Channels.PluginChannel do
  @moduledoc """
  Phoenix Channel for plugin pod communication.

  Topic: "plugin:{plugin_id}"

  Plugin → Agent messages:
    - "register"       %{entity_type_uri}
    - "entity_create"  %{request_id, entity}
    - "entity_update"  %{request_id, entity_id, attrs}
    - "entity_delete"  %{request_id, entity_id}

  Agent → Plugin messages:
    - "welcome"         %{plugin_id}
    - "entity_response" %{request_id, status, entity_id?}
    - "entity_changed"  %{entity_id, data}
    - "error"           %{request_id, code, message}
  """

  use Phoenix.Channel
  require Logger

  alias Eos.K8s.Client, as: K8sClient
  alias Eos.Plugins.Registry
  alias Eos.Broker.{Client, SubscriptionManager}

  @impl true
  def join("plugin:" <> plugin_id, _params, socket) do
    if socket.assigns.plugin_id == plugin_id do
      {:ok, assign(socket, :plugin_id, plugin_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("register", %{"entity_type_uri" => entity_type_uri}, socket) do
    plugin_id = socket.assigns.plugin_id

    case resolve_broker_config(plugin_id) do
      {:ok, broker_config} ->
        Registry.register(plugin_id, %{
          entity_type_uri: entity_type_uri,
          broker_config: broker_config,
          channel_pid: self()
        })

        Task.start(fn ->
          case SubscriptionManager.subscribe(plugin_id, entity_type_uri, broker_config) do
            {:ok, sub_id} ->
              Registry.put_subscription_id(plugin_id, sub_id)

              Logger.info(
                "[PluginChannel] Plugin #{plugin_id} registered, subscription #{sub_id}"
              )

            {:error, reason} ->
              Logger.error(
                "[PluginChannel] Subscription failed for #{plugin_id}: #{inspect(reason)}"
              )
          end
        end)

        {:reply, {:ok, %{plugin_id: plugin_id}}, socket}

      {:error, reason} ->
        Logger.error(
          "[PluginChannel] Broker config resolution failed for #{plugin_id}: #{inspect(reason)}"
        )

        {:reply, {:error, %{code: "broker_config_error", message: inspect(reason)}}, socket}
    end
  end

  def handle_in("entity_create", %{"request_id" => req_id, "entity" => entity}, socket) do
    plugin_id = socket.assigns.plugin_id

    case ensure_broker_config(plugin_id) do
      {:ok, broker} ->
        Task.start(fn ->
          result = Client.create_entity(entity, broker)
          reply_entity_response(socket, req_id, result)
        end)

        {:noreply, socket}

      {:error, reason} ->
        {:reply,
         {:error,
          %{request_id: req_id, code: "not_registered", message: inspect(reason)}},
         socket}
    end
  end

  def handle_in(
        "entity_update",
        %{"request_id" => req_id, "entity_id" => entity_id, "attrs" => attrs},
        socket
      ) do
    plugin_id = socket.assigns.plugin_id

    case ensure_broker_config(plugin_id) do
      {:ok, broker} ->
        Task.start(fn ->
          result = Client.update_entity(entity_id, attrs, broker)
          reply_entity_response(socket, req_id, result)
        end)

        {:noreply, socket}

      {:error, reason} ->
        {:reply,
         {:error,
          %{request_id: req_id, code: "not_registered", message: inspect(reason)}},
         socket}
    end
  end

  def handle_in("entity_delete", %{"request_id" => req_id, "entity_id" => entity_id}, socket) do
    plugin_id = socket.assigns.plugin_id

    case ensure_broker_config(plugin_id) do
      {:ok, broker} ->
        Task.start(fn ->
          result = Client.delete_entity(entity_id, broker)
          reply_entity_response(socket, req_id, result)
        end)

        {:noreply, socket}

      {:error, reason} ->
        {:reply,
         {:error,
          %{request_id: req_id, code: "not_registered", message: inspect(reason)}},
         socket}
    end
  end

  def handle_in(event, _payload, socket) do
    Logger.debug("[PluginChannel] Unknown event #{event} from #{socket.assigns.plugin_id}")
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    plugin_id = socket.assigns.plugin_id
    Logger.info("[PluginChannel] Plugin #{plugin_id} disconnected")
    Registry.unregister(plugin_id)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_broker_config(plugin_id) do
    with {:ok, plugin} <- K8sClient.get_plugin(plugin_id),
         broker_ref when is_binary(broker_ref) <- get_in(plugin, ["spec", "brokerRef"]),
         {:ok, broker} <- K8sClient.get_broker(broker_ref),
         {:ok, token} <- read_broker_token(broker) do
      {:ok,
       %{
         url: get_in(broker, ["spec", "url"]),
         token: token,
         tenant: get_in(broker, ["spec", "tenant"])
       }}
    else
      nil -> {:error, "brokerRef not set in plugin spec"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_broker_config(plugin_id) do
    case Registry.lookup(plugin_id) do
      {:ok, %{broker_config: broker}} ->
        {:ok, broker}

      :error ->
        with {:ok, broker} <- resolve_broker_config(plugin_id) do
          Registry.register(plugin_id, %{
            entity_type_uri: "unknown",
            broker_config: broker,
            channel_pid: self()
          })

          {:ok, broker}
        end
    end
  end

  defp read_broker_token(broker) do
    secret_name = get_in(broker, ["spec", "tokenSecretRef", "name"])
    secret_key = get_in(broker, ["spec", "tokenSecretRef", "key"]) || "token"

    case K8sClient.read_secret_value(secret_name, secret_key) do
      {:ok, nil} ->
        {:error, "broker token secret key '#{secret_key}' not found in '#{secret_name}'"}

      {:ok, token} ->
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reply_entity_response(socket, req_id, result) do
    msg =
      case result do
        {:ok, entity_id} -> %{request_id: req_id, status: "ok", entity_id: entity_id}
        {:error, reason} -> %{request_id: req_id, status: "error", reason: inspect(reason)}
      end

    Phoenix.Channel.push(socket, "entity_response", msg)
  end

  # ---------------------------------------------------------------------------
  # Push entity_changed notification from the notification controller
  # ---------------------------------------------------------------------------

  def push_entity_changed(channel_pid, entity_id, data) do
    send(channel_pid, {:push_entity_changed, entity_id, data})
  end

  @impl true
  def handle_info({:push_entity_changed, entity_id, data}, socket) do
    push(socket, "entity_changed", %{entity_id: entity_id, data: data})
    {:noreply, socket}
  end
end
