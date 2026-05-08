defmodule EosWeb.DashboardLive do
  use EosWeb, :live_view
  alias Eos.Plugins.Registry
  alias Eos.K8s.Client, as: K8sClient

  @broker_check_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eos.PubSub, "plugins")
      Process.send_after(self(), :check_brokers, @broker_check_interval)
    end

    {:ok, socket |> assign_new(:current_scope, fn -> nil end) |> assign_stats() |> load_brokers()}
  end

  @impl true
  def handle_info({event, _}, socket) when event in [:plugin_registered, :plugin_unregistered] do
    {:noreply, assign_stats(socket)}
  end

  def handle_info(:check_brokers, socket) do
    Process.send_after(self(), :check_brokers, @broker_check_interval)
    {:noreply, load_brokers(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh_brokers", _, socket) do
    {:noreply, load_brokers(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto px-4 py-10 space-y-8">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
          <p class="mt-1 text-sm text-base-content/50">EOS IoT Agent — real-time overview</p>
        </div>

        <%!-- Stats --%>
        <div class="grid grid-cols-3 gap-4">
          <.stat_card label="Total Plugins" value={@total} />
          <.stat_card label="Connected" value={@connected} color="text-success" />
          <.stat_card label="Offline" value={@total - @connected} color="text-warning" />
        </div>

        <%!-- Brokers --%>
        <div>
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-lg font-semibold text-base-content">Context Brokers</h2>
            <div class="flex items-center gap-2">
              <button
                phx-click="refresh_brokers"
                class="p-1.5 text-base-content/40 hover:text-base-content rounded-lg hover:bg-base-200 transition-colors"
                title="Refresh"
              >
                <.icon name="hero-arrow-path" class="w-4 h-4" />
              </button>
              <.link navigate={~p"/brokers"} class="text-sm text-primary hover:underline">
                Manage →
              </.link>
            </div>
          </div>

          <%= if @brokers == [] do %>
            <div class="p-5 rounded-xl border border-dashed border-base-300 flex items-center justify-between">
              <p class="text-sm text-base-content/40">No brokers configured.</p>
              <.link
                navigate={~p"/brokers?action=new"}
                class="text-sm text-primary hover:underline font-medium"
              >
                Add one →
              </.link>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for broker <- @brokers do %>
                <% bname = get_in(broker, ["metadata", "name"])
                burl = get_in(broker, ["spec", "url"])
                btenant = get_in(broker, ["spec", "tenant"]) %>
                <div class="flex items-center gap-3 px-4 py-3 rounded-xl bg-base-100 border border-base-300">
                  <div class="flex-shrink-0 w-8 h-8 bg-primary/10 rounded-lg flex items-center justify-center">
                    <.icon name="hero-server" class="w-4 h-4 text-primary" />
                  </div>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-medium text-base-content">{bname}</p>
                    <p class="text-xs text-base-content/40 truncate font-mono">{burl} · tenant: {btenant}</p>
                  </div>
                  <a
                    href={burl}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="p-1 text-base-content/30 hover:text-primary rounded transition-colors"
                    title="Open broker"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                  </a>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Active Plugin Sessions --%>
        <div>
          <h2 class="text-lg font-semibold text-base-content mb-3">Active Plugin Sessions</h2>
          <%= if @plugins == [] do %>
            <div class="p-5 rounded-xl border border-dashed border-base-300 text-center">
              <p class="text-sm text-base-content/40">No plugins currently connected</p>
            </div>
          <% else %>
            <div class="overflow-hidden rounded-xl border border-base-300">
              <table class="min-w-full divide-y divide-base-300">
                <thead class="bg-base-200/50">
                  <tr>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Plugin</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Entity Type</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Broker</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Subscription</th>
                    <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Connected</th>
                  </tr>
                </thead>
                <tbody class="bg-base-100 divide-y divide-base-200">
                  <%= for p <- @plugins do %>
                    <tr class="hover:bg-base-200/40 transition-colors">
                      <td class="px-4 py-3">
                        <.link
                          navigate={~p"/plugins/#{p.plugin_id}"}
                          class="text-sm font-medium text-primary hover:underline"
                        >
                          {p.plugin_id}
                        </.link>
                      </td>
                      <td class="px-4 py-3 font-mono text-xs text-base-content/50">{p.entity_type_uri}</td>
                      <td class="px-4 py-3 text-xs text-base-content/50 truncate max-w-xs">
                        {get_in(p, [:broker_config, :url]) || "—"}
                      </td>
                      <td class="px-4 py-3 font-mono text-xs text-base-content/50">
                        {p.subscription_id || "pending…"}
                      </td>
                      <td class="px-4 py-3 text-xs text-base-content/50">
                        {Calendar.strftime(p.connected_at, "%Y-%m-%d %H:%M:%S")}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <div class="flex gap-3">
          <.link
            navigate={~p"/plugins"}
            class="px-4 py-2 text-sm font-medium bg-primary text-primary-content rounded-lg hover:opacity-90 transition-opacity"
          >
            Manage Plugins
          </.link>
          <.link
            navigate={~p"/brokers"}
            class="px-4 py-2 text-sm font-medium text-base-content/70 bg-base-200 rounded-lg hover:bg-base-300 transition-colors"
          >
            Manage Brokers
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :color, fn -> "text-base-content" end)

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl p-5 shadow-sm">
      <p class="text-sm text-base-content/50">{@label}</p>
      <p class={"text-3xl font-bold mt-1 #{@color}"}>{@value}</p>
    </div>
    """
  end

  defp assign_stats(socket) do
    plugins = Registry.all()

    socket
    |> assign(:plugins, plugins)
    |> assign(:total, length(plugins))
    |> assign(:connected, length(plugins))
  end

  defp load_brokers(socket) do
    brokers =
      case K8sClient.list_brokers() do
        {:ok, %{"items" => items}} -> items
        _ -> []
      end

    assign(socket, :brokers, brokers)
  end
end
