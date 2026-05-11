defmodule Eos.Broker.Client do
  @moduledoc """
  HTTP client for the Phaeton NGSI-LD context broker.

  Configuration (via env or application config):
    - PHAETON_URL        — base URL of the broker, e.g. http://phaeton:4000
    - PHAETON_AGENT_TOKEN — Bearer token for the agent user in Phaeton
  """

  require Logger

  defp base_url do
    Application.fetch_env!(:eos, :phaeton_url)
  end

  defp agent_token do
    Application.fetch_env!(:eos, :phaeton_agent_token)
  end

  def ping do
    case Req.get(base_req(nil), url: "/types", receive_timeout: 5_000) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: status}} -> {:error, status}
      {:error, reason} -> {:error, reason}
    end
  end

  def ping(broker_config) when is_map(broker_config) do
    case Req.get(base_req(broker_config), url: "/types", receive_timeout: 5_000) do
      {:ok, %{status: status}} when status in [200, 204] -> :ok
      {:ok, %{status: status}} -> {:error, status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_req(config) when is_map(config) do
    %{url: url, token: token, tenant: tenant} = config

    headers =
      [{"authorization", "Bearer #{token}"}] ++
        if tenant, do: [{"ngsild-tenant", tenant}], else: []

    Req.new(
      base_url: url <> "/ngsi-ld/v1",
      headers: headers,
      json: true
    )
  end

  defp base_req(tenant) do
    headers =
      [{"authorization", "Bearer #{agent_token()}"}] ++
        if tenant, do: [{"ngsild-tenant", tenant}], else: []

    Req.new(
      base_url: base_url() <> "/ngsi-ld/v1",
      headers: headers,
      json: true
    )
  end

  # ---------------------------------------------------------------------------
  # Entities
  # ---------------------------------------------------------------------------

  def create_entity(entity), do: create_entity(entity, nil)

  def create_entity(entity, tenant) do
    entity_id = entity["id"]

    case Req.post(base_req(tenant), url: "/entities", json: entity) do
      {:ok, %{status: status}} when status in [200, 201] ->
        {:ok, entity_id}

      {:ok, %{status: 409}} ->
        # Already exists — treat as success (idempotent creation)
        {:ok, entity_id}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] create_entity failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_entity(entity_id, attrs), do: update_entity(entity_id, attrs, nil)

  def update_entity(entity_id, attrs, tenant) do
    case Req.patch(base_req(tenant), url: "/entities/#{URI.encode(entity_id)}/attrs", json: attrs) do
      {:ok, %{status: status}} when status in [200, 204] ->
        {:ok, entity_id}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] update_entity failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_entity(entity_id), do: delete_entity(entity_id, nil)

  def delete_entity(entity_id, tenant) do
    case Req.delete(base_req(tenant), url: "/entities/#{URI.encode(entity_id)}") do
      {:ok, %{status: status}} when status in [200, 204] ->
        {:ok, entity_id}

      {:ok, %{status: 404}} ->
        {:ok, entity_id}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] delete_entity failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_entities(type_uri), do: list_entities(type_uri, nil)

  def list_entities(type_uri, tenant) do
    case Req.get(base_req(tenant), url: "/entities", params: [type: type_uri]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Subscriptions
  # ---------------------------------------------------------------------------

  def create_subscription(subscription_body), do: create_subscription(subscription_body, nil)

  def create_subscription(subscription_body, tenant) do
    case Req.post(base_req(tenant), url: "/subscriptions", json: subscription_body) do
      {:ok, %{status: status, headers: headers}} when status in [200, 201] ->
        sub_id =
          headers
          |> Enum.find_value(fn {k, v} -> if String.downcase(k) == "location", do: v end)
          |> extract_subscription_id()

        {:ok, sub_id}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] create_subscription failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_subscription(sub_id), do: get_subscription(sub_id, nil)

  def get_subscription(sub_id, tenant) do
    case Req.get(base_req(tenant), url: "/subscriptions/#{URI.encode(sub_id)}") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        :not_found

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] get_subscription failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_subscription(sub_id), do: delete_subscription(sub_id, nil)

  def delete_subscription(sub_id, tenant) do
    case Req.delete(base_req(tenant), url: "/subscriptions/#{URI.encode(sub_id)}") do
      {:ok, %{status: status}} when status in [200, 204] ->
        :ok

      {:ok, %{status: 404}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[Broker] delete_subscription failed #{status}: #{inspect(body)}")
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp extract_subscription_id(nil), do: nil

  defp extract_subscription_id(location) when is_list(location) do
    location |> List.first() |> extract_subscription_id()
  end

  defp extract_subscription_id(location) when is_binary(location) do
    location |> String.split("/") |> List.last()
  end
end
