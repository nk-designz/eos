defmodule EosWeb.Channels.PluginV2CompatSerializer do
  @moduledoc """
  Compatibility serializer for plugin socket clients using V2 payload format.

  Some clients send `join_ref: null` on channel events after a successful join.
  Phoenix treats that as a stale join_ref and drops messages. By normalizing
  decoded message join_ref to `nil`, Phoenix accepts those events.
  """

  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.Message

  @impl true
  def fastlane!(broadcast), do: Phoenix.Socket.V2.JSONSerializer.fastlane!(broadcast)

  @impl true
  def encode!(message), do: Phoenix.Socket.V2.JSONSerializer.encode!(message)

  @impl true
  def decode!(raw_message, opts) do
    case Phoenix.Socket.V2.JSONSerializer.decode!(raw_message, opts) do
      %Message{} = message -> %Message{message | join_ref: nil}
      other -> other
    end
  end
end
