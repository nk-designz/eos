defmodule EosWeb.Channels.PluginSocket do
  use Phoenix.Socket

  channel "plugin:*", EosWeb.Channels.PluginChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Eos.Plugins.Token.verify(token) do
      {:ok, plugin_id} ->
        {:ok, assign(socket, :plugin_id, plugin_id)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "plugin_socket:#{socket.assigns.plugin_id}"
end
