defmodule Eos.K8s.Client do
  @moduledoc """
  Thin wrapper around the `k8s` library. Provides a configured connection
  and helper functions for Plugin CRD operations.
  """

  @group "eos.io"
  @version "v1alpha1"
  @kind "Plugin"

  def conn do
    case Application.get_env(:eos, :k8s_conn) do
      nil -> K8s.Conn.from_service_account()
      path when is_binary(path) -> K8s.Conn.from_file(path)
      conn -> {:ok, conn}
    end
  end

  def namespace do
    Application.get_env(:eos, :k8s_namespace, "default")
  end

  def list_plugins do
    with {:ok, c} <- conn() do
      op = K8s.Client.list(@group <> "/" <> @version, @kind, namespace: namespace())
      K8s.Client.run(c, op)
    end
  end

  def get_plugin(name) do
    with {:ok, c} <- conn() do
      op = K8s.Client.get(@group <> "/" <> @version, @kind, namespace: namespace(), name: name)
      K8s.Client.run(c, op)
    end
  end

  def patch_plugin_status(name, status_patch) do
    with {:ok, c} <- conn() do
      resource = %{"status" => status_patch}

      op =
        K8s.Client.patch(
          @group <> "/" <> @version,
          {@kind, "status"},
          [namespace: namespace(), name: name],
          resource,
          :merge
        )

      K8s.Client.run(c, op)
    end
  end

  def create_pod(pod_manifest) do
    with {:ok, c} <- conn() do
      op = K8s.Client.create(pod_manifest)
      K8s.Client.run(c, op)
    end
  end

  def delete_pod(name) do
    with {:ok, c} <- conn() do
      op = K8s.Client.delete("v1", "Pod", namespace: namespace(), name: name)
      K8s.Client.run(c, op)
    end
  end

  def get_pod(name) do
    with {:ok, c} <- conn() do
      op = K8s.Client.get("v1", "Pod", namespace: namespace(), name: name)
      K8s.Client.run(c, op)
    end
  end

  def get_pod_logs(pod_name, tail_lines \\ 150) do
    with {:ok, c} <- conn() do
      op = K8s.Client.get("v1", "pods/log", namespace: namespace(), name: pod_name)
      op = %{op | query_params: [tailLines: tail_lines]}
      K8s.Client.run(c, op)
    end
  end

  def watch_plugins do
    with {:ok, c} <- conn() do
      op = K8s.Client.watch(@group <> "/" <> @version, @kind, namespace: namespace())
      K8s.Client.stream(c, op)
    end
  end

  def create_secret(name, string_data) do
    with {:ok, c} <- conn() do
      secret = %{
        "apiVersion" => "v1",
        "kind" => "Secret",
        "metadata" => %{"name" => name, "namespace" => namespace()},
        "stringData" => string_data
      }

      op = K8s.Client.create(secret)
      K8s.Client.run(c, op)
    end
  end

  def update_secret(name, string_data) do
    with {:ok, c} <- conn() do
      secret = %{
        "apiVersion" => "v1",
        "kind" => "Secret",
        "metadata" => %{"name" => name, "namespace" => namespace()},
        "stringData" => string_data
      }

      op = K8s.Client.patch("v1", "Secret", [namespace: namespace(), name: name], secret)
      K8s.Client.run(c, op)
    end
  end

  def delete_secret(name) do
    with {:ok, c} <- conn() do
      op = K8s.Client.delete("v1", "Secret", namespace: namespace(), name: name)
      K8s.Client.run(c, op)
    end
  end

  def read_secret_value(secret_name, key) do
    with {:ok, c} <- conn(),
         {:ok, secret} <-
           K8s.Client.run(
             c,
             K8s.Client.get("v1", "Secret", namespace: namespace(), name: secret_name)
           ) do
      value =
        case secret["data"] do
          data when is_map(data) ->
            case Map.get(data, key) do
              nil -> nil
              encoded -> Base.decode64!(encoded)
            end

          _ ->
            nil
        end

      {:ok, value}
    end
  end

  # ---------------------------------------------------------------------------
  # Broker CRD operations
  # ---------------------------------------------------------------------------

  @broker_kind "Broker"

  def list_brokers do
    with {:ok, c} <- conn() do
      op = K8s.Client.list(@group <> "/" <> @version, @broker_kind, namespace: namespace())
      K8s.Client.run(c, op)
    end
  end

  def get_broker(name) do
    with {:ok, c} <- conn() do
      op =
        K8s.Client.get(@group <> "/" <> @version, @broker_kind,
          namespace: namespace(),
          name: name
        )

      K8s.Client.run(c, op)
    end
  end

  def create_broker(manifest) do
    with {:ok, c} <- conn() do
      op = K8s.Client.create(manifest)
      K8s.Client.run(c, op)
    end
  end

  def delete_broker(name) do
    with {:ok, c} <- conn() do
      op =
        K8s.Client.delete(@group <> "/" <> @version, @broker_kind,
          namespace: namespace(),
          name: name
        )

      K8s.Client.run(c, op)
    end
  end

  def patch_broker_status(name, status_patch) do
    with {:ok, c} <- conn() do
      resource = %{"status" => status_patch}

      op =
        K8s.Client.patch(
          @group <> "/" <> @version,
          {@broker_kind, "status"},
          [namespace: namespace(), name: name],
          resource,
          :merge
        )

      K8s.Client.run(c, op)
    end
  end
end
