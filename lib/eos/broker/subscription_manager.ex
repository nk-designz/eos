defmodule Eos.Broker.SubscriptionManager do
  @moduledoc """
  Creates and removes Phaeton subscriptions on behalf of plugins.

  When a plugin registers, this module POSTs an NGSI-LD subscription to
  Phaeton so that any changes to entities of that type are forwarded to
  the agent's /webhooks/phaeton endpoint.
  """

  require Logger

  alias Eos.Broker.Client

  def subscribe(plugin_id, entity_type_uri), do: subscribe(plugin_id, entity_type_uri, nil)

  def subscribe(plugin_id, entity_type_uri, broker_config) do
    webhook_url = webhook_url()

    subscription = %{
      "id" => "urn:ngsi-ld:Subscription:eos:#{plugin_id}",
      "type" => "Subscription",
      "entities" => [%{"type" => entity_type_uri}],
      "notification" => %{
        "endpoint" => %{
          "uri" => webhook_url,
          "accept" => "application/json"
        }
      }
    }

    case Client.create_subscription(subscription, broker_config) do
      {:ok, sub_id} ->
        Logger.info("[SubscriptionManager] Subscribed plugin #{plugin_id} → #{sub_id}")
        {:ok, sub_id}

      {:error, reason} = err ->
        Logger.error(
          "[SubscriptionManager] Failed to subscribe plugin #{plugin_id}: #{inspect(reason)}"
        )

        err
    end
  end

  def delete(sub_id), do: delete(sub_id, nil)

  def delete(sub_id, broker_config) do
    case Client.delete_subscription(sub_id, broker_config) do
      :ok ->
        Logger.info("[SubscriptionManager] Deleted subscription #{sub_id}")
        :ok

      {:error, reason} ->
        Logger.warning(
          "[SubscriptionManager] Failed to delete subscription #{sub_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp webhook_url do
    base = Application.fetch_env!(:eos, :agent_base_url)
    "#{base}/webhooks/phaeton"
  end
end
