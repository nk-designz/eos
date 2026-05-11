defmodule EosWeb.NotificationController do
  @moduledoc """
  Receives NGSI-LD change notifications from Phaeton and dispatches them
  to the appropriate plugin WebSocket channel.
  """

  use EosWeb, :controller
  require Logger

  alias Eos.Plugins.Registry
  alias EosWeb.Channels.PluginChannel

  def receive(conn, params) do
    notifications = params["data"] || []
    subscription_id = params["subscriptionId"]

    Logger.debug(
      "[NotificationController] Received notification for subscription #{subscription_id}, #{length(notifications)} entities"
    )

    Enum.each(notifications, fn entity ->
      entity_id = entity["id"]
      entity_type = entity["type"]

      Registry.find_by_entity_type(entity_type)
      |> Enum.each(fn %{plugin_id: plugin_id, channel_pid: pid} ->
        PluginChannel.push_entity_changed(pid, entity_id, entity)

        Phoenix.PubSub.broadcast(
          Eos.PubSub,
          "plugin_events:#{plugin_id}",
          {:entity_event, "#{entity_type} changed: #{entity_id}"}
        )
      end)
    end)

    send_resp(conn, 204, "")
  end
end
