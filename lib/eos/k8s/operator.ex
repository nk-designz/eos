defmodule Eos.K8s.Operator do
  @moduledoc """
  GenServer that performs an initial list of Plugin CRDs and then watches for
  changes, dispatching reconcile calls to `Eos.K8s.PluginController`.
  """

  use GenServer
  require Logger

  @retry_delay_ms 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :start_watch)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:start_watch, state) do
    case do_list_and_watch() do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "[Operator] Watch failed: #{inspect(reason)}. Retrying in #{@retry_delay_ms}ms"
        )

        Process.send_after(self(), :start_watch, @retry_delay_ms)
        {:noreply, state}
    end
  end

  def handle_info({:watch_event, event}, state) do
    handle_watch_event(event)
    {:noreply, state}
  end

  def handle_info({:watch_done, reason}, state) do
    Logger.info("[Operator] Watch stream ended (#{inspect(reason)}). Restarting.")
    Process.send_after(self(), :start_watch, @retry_delay_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_list_and_watch do
    with {:ok, stream} <- Eos.K8s.Client.watch_plugins() do
      operator_pid = self()

      Task.start(fn ->
        result =
          Enum.reduce_while(stream, :ok, fn event, acc ->
            send(operator_pid, {:watch_event, event})
            {:cont, acc}
          end)

        send(operator_pid, {:watch_done, result})
      end)

      :ok
    end
  end

  defp handle_watch_event(%{"type" => type, "object" => plugin}) do
    name = get_in(plugin, ["metadata", "name"])

    case type do
      t when t in ["ADDED", "MODIFIED"] ->
        Logger.debug("[Operator] #{t} Plugin/#{name}")
        Eos.K8s.PluginController.reconcile(plugin)

      "DELETED" ->
        Logger.debug("[Operator] DELETED Plugin/#{name}")
        Eos.K8s.PluginController.cleanup(plugin)

      other ->
        Logger.debug("[Operator] Unknown event type #{other}")
    end
  end

  defp handle_watch_event(event) do
    Logger.debug("[Operator] Unexpected event shape: #{inspect(event)}")
  end
end
