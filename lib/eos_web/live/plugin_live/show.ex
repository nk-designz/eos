defmodule EosWeb.PluginLive.Show do
  use EosWeb, :live_view
  require Logger

  alias Eos.Plugins.Registry
  alias Eos.Broker.Client

  @impl true
  def mount(%{"id" => plugin_name}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eos.PubSub, "plugins")
      Phoenix.PubSub.subscribe(Eos.PubSub, "plugin_events:#{plugin_name}")
      send(self(), :refresh_logs)
    end

    socket =
      socket
      |> assign(:plugin_name, plugin_name)
      |> assign(:logs, nil)
      |> load_plugin(plugin_name)
      |> load_entities(plugin_name)
      |> assign(:events, [])

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Plugin: #{socket.assigns.plugin_name}")}
  end

  @impl true
  def handle_info({event, _}, socket) when event in [:plugin_registered, :plugin_unregistered] do
    {:noreply, load_plugin(socket, socket.assigns.plugin_name)}
  end

  def handle_info({:entity_event, event}, socket) do
    events = [event | Enum.take(socket.assigns.events, 49)]
    {:noreply, assign(socket, :events, events)}
  end

  def handle_info(:refresh_logs, socket) do
    Process.send_after(self(), :refresh_logs, 5_000)
    {:noreply, fetch_logs(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh_entities", _, socket) do
    {:noreply, load_entities(socket, socket.assigns.plugin_name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="p-6 space-y-6 max-w-screen-xl mx-auto">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/plugins"} class="btn btn-ghost btn-sm">← Back</.link>
          <h1 class="text-2xl font-bold">{@plugin_name}</h1>
          <%= if @connected do %>
            <span class="badge badge-success">Connected</span>
          <% else %>
            <span class="badge badge-ghost">Disconnected</span>
          <% end %>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="card bg-base-200 shadow p-4 space-y-2">
            <h2 class="font-semibold">Configuration</h2>
            <%= if @plugin do %>
              <% spec = @plugin["spec"] || %{} %>
              <.info_row label="Image" value={spec["image"]} mono />
              <.info_row label="Broker Ref" value={spec["brokerRef"]} />
              <.info_row label="Tenant" value={spec["tenant"] || "default"} />
              <.info_row label="Replicas" value={spec["replicas"] || 1} />
            <% end %>
          </div>

          <div class="card bg-base-200 shadow p-4 space-y-2">
            <h2 class="font-semibold">Runtime Status</h2>
            <%= if @plugin do %>
              <% status = @plugin["status"] || %{} %>
              <.info_row label="Phase" value={status["phase"] || "Unknown"} />
              <.info_row label="Pod" value={status["podName"] || "—"} mono />
              <%= if status["errorMessage"] do %>
                <.info_row label="Error" value={status["errorMessage"]} />
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div class="card bg-base-200 shadow p-4 space-y-2">
            <h2 class="font-semibold">Registration</h2>
            <%= if @registered do %>
              <.info_row label="Entity Type URI" value={@registered.entity_type_uri} mono />
              <.info_row
                label="Subscription ID"
                value={@registered.subscription_id || "Pending…"}
                mono
              />
              <.info_row label="Connected At" value={format_datetime(@registered.connected_at)} />
            <% else %>
              <p class="text-xs text-base-content/40">Not registered yet</p>
            <% end %>
          </div>

          <div class="card bg-base-200 shadow p-4 space-y-2">
            <h2 class="font-semibold">Broker Config</h2>
            <%= if @registered do %>
              <.info_row label="Broker URL" value={@registered.broker_config.url} mono />
              <.info_row label="Tenant" value={@registered.broker_config.tenant || "default"} />
              <.info_row
                label="Auth"
                value={if(@registered.broker_config.token, do: "Bearer token set", else: "None")}
              />
            <% else %>
              <p class="text-xs text-base-content/40">Not registered yet</p>
            <% end %>
          </div>
        </div>

        <div>
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-lg font-semibold">Entities ({length(@entities)})</h2>
            <button phx-click="refresh_entities" class="btn btn-ghost btn-xs">Refresh</button>
          </div>
          <div class="overflow-x-auto">
            <table class="table table-zebra w-full">
              <thead>
                <tr>
                  <th>Entity ID</th>
                  <th>Type</th>
                  <th>Modified At</th>
                </tr>
              </thead>
              <tbody>
                <%= for entity <- @entities do %>
                  <tr>
                    <td class="font-mono text-xs">{entity["id"]}</td>
                    <td class="font-mono text-xs">{entity["type"]}</td>
                    <td>{get_in(entity, ["modifiedAt", "value"]) || "—"}</td>
                  </tr>
                <% end %>
                <%= if @entities == [] do %>
                  <tr>
                    <td colspan="3" class="text-center text-base-content/50">No entities yet</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <div>
          <h2 class="text-lg font-semibold mb-2">Recent Events</h2>
          <div class="bg-base-300 rounded-box p-4 font-mono text-xs space-y-1 max-h-64 overflow-y-auto">
            <%= if @events == [] do %>
              <p class="text-base-content/40">No events yet…</p>
            <% end %>
            <%= for event <- @events do %>
              <p>{event}</p>
            <% end %>
          </div>
        </div>

        <%!-- Pod Logs --%>
        <div>
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-lg font-semibold">Pod Logs</h2>
            <span class="text-xs text-base-content/40">auto-refreshes every 5 s</span>
          </div>
          <%= cond do %>
            <% is_nil(@logs) and not @connected -> %>
              <div class="bg-base-200 rounded-xl p-6 text-center text-sm text-base-content/40">
                No logs yet — pod may still be starting.
              </div>
            <% is_nil(@logs) -> %>
              <div class="bg-base-200 rounded-xl p-6 text-center text-sm text-base-content/40">
                Loading logs…
              </div>
            <% @logs == "" -> %>
              <div class="bg-base-200 rounded-xl p-6 text-center text-sm text-base-content/40">
                No log output yet.
              </div>
            <% true -> %>
              <div
                id="pod-logs"
                class="relative rounded-xl bg-black overflow-hidden"
              >
                <div class="flex items-center justify-between px-4 py-2 bg-black border-b border-white/10">
                  <span class="font-mono text-xs text-white/40">
                    {get_in(@plugin, ["status", "podName"]) || "eos-plugin-#{@plugin_name}"}
                  </span>
                  <span class="flex items-center gap-1.5 text-xs text-success">
                    <span class="w-1.5 h-1.5 rounded-full bg-success animate-pulse"></span> live
                  </span>
                </div>
                <pre
                  id="pod-logs-pre"
                  phx-hook=".ScrollBottom"
                  class="p-4 font-mono text-xs text-white overflow-x-auto max-h-96 overflow-y-auto whitespace-pre-wrap break-all"
                  phx-no-curly-interpolation
                ><%= @logs %></pre>
              </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollBottom">
      export default {
        updated() {
          this.el.scrollTop = this.el.scrollHeight
        }
      }
    </script>
    """
  end

  defp info_row(assigns) do
    assigns = assign_new(assigns, :mono, fn -> false end)

    ~H"""
    <div class="flex gap-2 text-sm">
      <span class="text-base-content/60 w-32 shrink-0">{@label}</span>
      <span class={if @mono, do: "font-mono truncate", else: "truncate"}>{@value}</span>
    </div>
    """
  end

  defp load_plugin(socket, plugin_name) do
    plugin =
      case Eos.K8s.Client.get_plugin(plugin_name) do
        {:ok, p} -> p
        _ -> nil
      end

    connected = Registry.connected?(plugin_name)

    registered =
      case Registry.lookup(plugin_name) do
        {:ok, entry} -> entry
        :error -> nil
      end

    socket
    |> assign(:plugin, plugin)
    |> assign(:connected, connected)
    |> assign(:registered, registered)
  end

  defp fetch_logs(socket) do
    # Pod name is always "eos-plugin-{plugin_name}" by controller convention.
    # We fall back to this because status.podName may not be set if the CRD
    # status subresource patch failed.
    pod_name =
      get_in(socket.assigns.plugin || %{}, ["status", "podName"]) ||
        "eos-plugin-#{socket.assigns.plugin_name}"

    logs =
      case Eos.K8s.Client.get_pod_logs(pod_name) do
        {:ok, text} when is_binary(text) and text != "" ->
          # Strip ANSI escape sequences (colors, bold, dim, etc.)
          String.replace(text, ~r/\x1b\[[0-9;]*[A-Za-z]/, "")

        _ ->
          nil
      end

    assign(socket, :logs, logs)
  end

  defp load_entities(socket, plugin_name) do
    entities =
      with {:ok, %{entity_type_uri: type_uri, broker_config: broker_config}} <-
             Registry.lookup(plugin_name),
           {:ok, list} <- Client.list_entities(type_uri, broker_config) do
        list
      else
        _ -> []
      end

    assign(socket, :entities, entities)
  end

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    datetime
    |> DateTime.truncate(:second)
    |> to_string()
  end

  defp format_datetime(nil), do: "—"
  defp format_datetime(value), do: to_string(value)
end
