defmodule Eos.Plugins.Registry do
  @moduledoc """
  ETS-backed registry mapping plugin_id to its runtime session.

  Stored per entry:
    %{
      plugin_id: String.t(),
      entity_type_uri: String.t(),
      broker_config: %{url: String.t(), token: String.t(), tenant: String.t() | nil},
      channel_pid: pid(),
      subscription_id: String.t() | nil,
      connected_at: DateTime.t()
    }
  """

  use GenServer

  @table :eos_plugin_registry

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register(plugin_id, attrs) do
    entry = Map.merge(attrs, %{plugin_id: plugin_id, connected_at: DateTime.utc_now()})
    :ets.insert(@table, {plugin_id, entry})
    Phoenix.PubSub.broadcast(Eos.PubSub, "plugins", {:plugin_registered, entry})
    :ok
  end

  def unregister(plugin_id) do
    :ets.delete(@table, plugin_id)
    Phoenix.PubSub.broadcast(Eos.PubSub, "plugins", {:plugin_unregistered, plugin_id})
    :ok
  end

  def put_subscription_id(plugin_id, sub_id) do
    case lookup(plugin_id) do
      {:ok, entry} ->
        updated = Map.put(entry, :subscription_id, sub_id)
        :ets.insert(@table, {plugin_id, updated})
        :ok

      :error ->
        :error
    end
  end

  def lookup(plugin_id) do
    case :ets.lookup(@table, plugin_id) do
      [{^plugin_id, entry}] -> {:ok, entry}
      [] -> :error
    end
  end

  def find_by_entity_type(entity_type_uri) do
    :ets.match_object(@table, {:"$1", %{entity_type_uri: entity_type_uri}})
    |> Enum.map(fn {_id, entry} -> entry end)
  end

  def all do
    :ets.tab2list(@table) |> Enum.map(fn {_id, entry} -> entry end)
  end

  def connected?(plugin_id) do
    match?({:ok, _}, lookup(plugin_id))
  end

  # ---------------------------------------------------------------------------
  # Server callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end
end
