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
    sub_id = subscription_id(plugin_id, entity_type_uri)

    subscription = %{
      "id" => sub_id,
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
        handle_subscription_collision(plugin_id, subscription, broker_config, reason, err)
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

  defp handle_subscription_collision(plugin_id, desired, broker_config, reason, original_error) do
    sub_id = desired["id"]

    case Client.get_subscription(sub_id, broker_config) do
      {:ok, existing} ->
        if compatible_subscription?(existing, desired) do
          Logger.info(
            "[SubscriptionManager] Existing subscription #{sub_id} matches desired config for #{plugin_id}, reusing it"
          )

          {:ok, sub_id}
        else
          Logger.warning(
            "[SubscriptionManager] Existing subscription #{sub_id} does not match desired config for #{plugin_id}, recreating"
          )

          with :ok <- Client.delete_subscription(sub_id, broker_config),
               {:ok, recreated_id} <- Client.create_subscription(desired, broker_config) do
            {:ok, recreated_id}
          else
            {:error, recreate_reason} = recreate_err ->
              Logger.error(
                "[SubscriptionManager] Failed to recreate subscription #{sub_id} for #{plugin_id}: #{inspect(recreate_reason)}"
              )

              recreate_err
          end
        end

      :not_found ->
        Logger.error(
          "[SubscriptionManager] Failed to subscribe plugin #{plugin_id}: #{inspect(reason)}"
        )

        original_error

      {:error, lookup_reason} ->
        Logger.error(
          "[SubscriptionManager] Failed to subscribe plugin #{plugin_id}: #{inspect(reason)} (lookup failed: #{inspect(lookup_reason)})"
        )

        original_error
    end
  end

  defp compatible_subscription?(existing, desired) do
    existing_type = existing |> get_in(["entities", Access.at(0), "type"])
    desired_type = desired |> get_in(["entities", Access.at(0), "type"])

    existing_endpoint = existing |> get_in(["notification", "endpoint", "uri"])
    desired_endpoint = desired |> get_in(["notification", "endpoint", "uri"])

    existing_accept = existing |> get_in(["notification", "endpoint", "accept"])
    desired_accept = desired |> get_in(["notification", "endpoint", "accept"])

    existing_type == desired_type and existing_endpoint == desired_endpoint and
      existing_accept == desired_accept
  end

  defp subscription_id(plugin_id, entity_type_uri) do
    plugin_part = to_camel_alnum(plugin_id)
    entity_part = to_camel_alnum(entity_type_uri)

    "urn:ngsi-ld:Subscription:eosIoTAgent#{plugin_part}#{entity_part}"
  end

  defp to_camel_alnum(value) when is_binary(value) do
    value
    |> String.split(~r/[^a-zA-Z0-9]+/, trim: true)
    |> Enum.map_join(&String.capitalize/1)
  end
end
