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
    end

    socket =
      socket
      |> assign(:plugin_name, plugin_name)
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
            <h2 class="font-semibold">Spec</h2>
            <%= if @plugin do %>
              <% spec = @plugin["spec"] || %{} %>
              <.info_row label="Image" value={spec["image"]} mono />
              <.info_row label="Entity Type" value={spec["entityTypeUri"]} mono />
              <.info_row label="Tenant" value={spec["tenant"] || "default"} />
              <.info_row label="Replicas" value={spec["replicas"] || 1} />
            <% end %>
          </div>

          <div class="card bg-base-200 shadow p-4 space-y-2">
            <h2 class="font-semibold">Status</h2>
            <%= if @plugin do %>
              <% status = @plugin["status"] || %{} %>
              <.info_row label="Phase" value={status["phase"] || "Unknown"} />
              <.info_row label="Pod" value={status["podName"] || "—"} mono />
              <.info_row label="Subscription ID" value={status["subscriptionId"] || "—"} mono />
              <.info_row label="Registered At" value={status["registeredAt"] || "—"} />
              <%= if status["errorMessage"] do %>
                <.info_row label="Error" value={status["errorMessage"]} />
              <% end %>
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
      </div>
    </Layouts.app>
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

    socket
    |> assign(:plugin, plugin)
    |> assign(:connected, connected)
  end

  defp load_entities(socket, plugin_name) do
    entities =
      with {:ok, %{entity_type_uri: type_uri, tenant: tenant}} <- Registry.lookup(plugin_name),
           {:ok, list} <- Client.list_entities(type_uri, tenant) do
        list
      else
        _ -> []
      end

    assign(socket, :entities, entities)
  end
end
