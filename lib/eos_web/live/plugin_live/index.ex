defmodule EosWeb.PluginLive.Index do
  use EosWeb, :live_view
  require Logger

  alias Eos.K8s.Client, as: K8sClient

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Eos.PubSub, "plugins")
    end

    socket =
      socket
      |> assign_new(:current_scope, fn -> nil end)
      |> load_plugins()
      |> load_brokers()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :page_title, "Plugins")

  defp apply_action(socket, :new, _params) do
    assign(socket, :page_title, "New Plugin")
  end

  @impl true
  def handle_info({event, _}, socket) when event in [:plugin_registered, :plugin_unregistered] do
    {:noreply, load_plugins(socket)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", %{"id" => plugin_name}, socket) do
    case K8sClient.get_plugin(plugin_name) do
      {:ok, plugin} ->
        Eos.K8s.PluginController.cleanup(plugin)
        {:noreply, socket |> put_flash(:info, "Plugin #{plugin_name} deleted") |> load_plugins()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Plugin #{plugin_name} not found")}
    end
  end

  def handle_event("save", %{"plugin" => plugin_params}, socket) do
    case create_plugin(plugin_params) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Plugin created")
         |> push_patch(to: ~p"/plugins")}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto px-4 py-10">
        <div class="flex items-start justify-between mb-8">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Plugins</h1>
            <p class="mt-1 text-sm text-base-content/50">
              Managed plugin pods connected to this IoT agent.
            </p>
          </div>
          <.link
            patch={~p"/plugins/new"}
            class="flex items-center gap-2 px-4 py-2 bg-primary text-primary-content text-sm font-medium rounded-lg hover:opacity-90 active:scale-95 transition-all"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Plugin
          </.link>
        </div>

        <%= if @live_action == :new do %>
          <.plugin_form brokers={@brokers} />
        <% end %>

        <%= if @plugins == [] do %>
          <div class="flex flex-col items-center justify-center py-24 border-2 border-dashed border-base-300 rounded-2xl">
            <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
              <.icon name="hero-cpu-chip" class="w-7 h-7 text-base-content/30" />
            </div>
            <p class="font-medium text-base-content/70">No plugins yet</p>
            <p class="text-sm text-base-content/40 mt-1">
              Create a plugin to start routing IoT data through this agent.
            </p>
          </div>
        <% else %>
          <div class="overflow-hidden rounded-xl border border-base-300">
            <table class="min-w-full divide-y divide-base-300">
              <thead class="bg-base-200/50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Name</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Image</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Broker</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Phase</th>
                  <th class="px-4 py-3 text-left text-xs font-medium text-base-content/50 uppercase tracking-wider">Connected</th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody class="bg-base-100 divide-y divide-base-200">
                <%= for plugin <- @plugins do %>
                  <% name = get_in(plugin, ["metadata", "name"])
                  spec = plugin["spec"] || %{}
                  status = plugin["status"] || %{}
                  phase = status["phase"] || "Unknown"
                  connected = Eos.Plugins.Registry.connected?(name) %>
                  <tr class="hover:bg-base-200/40 transition-colors">
                    <td class="px-4 py-3">
                      <.link
                        navigate={~p"/plugins/#{name}"}
                        class="font-medium text-primary hover:underline"
                      >
                        {name}
                      </.link>
                    </td>
                    <td class="px-4 py-3 font-mono text-xs text-base-content/50 max-w-xs truncate">
                      {spec["image"]}
                    </td>
                    <td class="px-4 py-3 text-sm text-base-content/70">
                      {spec["brokerRef"] || "—"}
                    </td>
                    <td class="px-4 py-3"><.phase_badge phase={phase} /></td>
                    <td class="px-4 py-3">
                      <span class={[
                        "inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full font-medium",
                        if(connected, do: "bg-success/15 text-success", else: "bg-base-200 text-base-content/40")
                      ]}>
                        <span class={["w-1.5 h-1.5 rounded-full", if(connected, do: "bg-success animate-pulse", else: "bg-base-content/20")]}></span>
                        {if connected, do: "Connected", else: "Offline"}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <button
                        phx-click="delete"
                        phx-value-id={name}
                        data-confirm={"Delete plugin '#{name}'?"}
                        class="p-1.5 text-base-content/30 hover:text-error hover:bg-error/10 rounded-lg transition-colors"
                        title="Delete"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp plugin_form(assigns) do
    ~H"""
    <div class="mb-8 p-6 bg-base-100 border border-base-300 rounded-2xl shadow-sm">
      <div class="flex items-center gap-2.5 mb-5">
        <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
          <.icon name="hero-cpu-chip" class="w-4 h-4 text-primary" />
        </div>
        <h2 class="text-base font-semibold text-base-content">New Plugin</h2>
      </div>
      <form id="plugin-form" phx-submit="save" class="space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-base-content/70 mb-1">
              Plugin Name <span class="text-error">*</span>
            </label>
            <input
              type="text"
              name="plugin[name]"
              placeholder="my-sensor-plugin"
              required
              class="w-full px-3 py-2 text-sm border border-base-300 rounded-lg bg-base-100 text-base-content focus:outline-none focus:ring-2 focus:ring-primary/50"
            />
            <p class="mt-1 text-xs text-base-content/40">Lowercase alphanumeric and hyphens</p>
          </div>

          <div>
            <label class="block text-sm font-medium text-base-content/70 mb-1">
              Context Broker <span class="text-error">*</span>
            </label>
            <select
              name="plugin[broker_ref]"
              required
              class="w-full px-3 py-2 text-sm border border-base-300 rounded-lg bg-base-100 text-base-content focus:outline-none focus:ring-2 focus:ring-primary/50"
            >
              <option value="" disabled selected>Select a broker…</option>
              <%= for broker <- @brokers do %>
                <% bname = get_in(broker, ["metadata", "name"])
                burl = get_in(broker, ["spec", "url"]) %>
                <option value={bname}>{bname} — {burl}</option>
              <% end %>
            </select>
            <%= if @brokers == [] do %>
              <p class="mt-1 text-xs text-warning">
                No brokers configured. <.link navigate={~p"/brokers?action=new"} class="underline">Create one first</.link>.
              </p>
            <% end %>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-base-content/70 mb-1">
            OCI Image <span class="text-error">*</span>
          </label>
          <input
            type="text"
            name="plugin[image]"
            placeholder="registry.example.com/my-plugin:latest"
            required
            class="w-full px-3 py-2 text-sm font-mono border border-base-300 rounded-lg bg-base-100 text-base-content focus:outline-none focus:ring-2 focus:ring-primary/50"
          />
        </div>

        <div class="flex gap-3 pt-3 border-t border-base-200">
          <button
            type="submit"
            class="px-4 py-2 text-sm font-medium bg-primary text-primary-content rounded-lg hover:opacity-90 transition-opacity"
          >
            Create Plugin
          </button>
          <.link
            patch={~p"/plugins"}
            class="px-4 py-2 text-sm font-medium text-base-content/70 bg-base-200 rounded-lg hover:bg-base-300 transition-colors"
          >
            Cancel
          </.link>
        </div>
      </form>
    </div>
    """
  end

  defp phase_badge(%{phase: "Running"} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-success/15 text-success">
      Running
    </span>
    """
  end

  defp phase_badge(%{phase: "Error"} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-error/15 text-error">
      Error
    </span>
    """
  end

  defp phase_badge(%{phase: "Stopped"} = assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-base-200 text-base-content/50">
      Stopped
    </span>
    """
  end

  defp phase_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-warning/15 text-warning">
      {@phase}
    </span>
    """
  end

  defp load_plugins(socket) do
    plugins =
      case K8sClient.list_plugins() do
        {:ok, %{"items" => items}} -> items
        _ -> []
      end

    assign(socket, :plugins, plugins)
  end

  defp load_brokers(socket) do
    brokers =
      case K8sClient.list_brokers() do
        {:ok, %{"items" => items}} -> items
        _ -> []
      end

    assign(socket, :brokers, brokers)
  end

  defp create_plugin(params) do
    name = String.trim(params["name"] || "")
    broker_ref = String.trim(params["broker_ref"] || "")
    image = String.trim(params["image"] || "")

    cond do
      not Regex.match?(~r/^[a-z0-9][a-z0-9\-]*[a-z0-9]$|^[a-z0-9]$/, name) ->
        {:error, "Invalid plugin name (lowercase alphanumeric and hyphens)"}

      broker_ref == "" ->
        {:error, "A context broker must be selected"}

      image == "" ->
        {:error, "OCI image is required"}

      true ->
        do_create_plugin(name, broker_ref, image)
    end
  end

  defp do_create_plugin(name, broker_ref, image) do
    manifest = %{
      "apiVersion" => "eos.io/v1alpha1",
      "kind" => "Plugin",
      "metadata" => %{
        "name" => name,
        "namespace" => K8sClient.namespace()
      },
      "spec" => %{
        "image" => image,
        "brokerRef" => broker_ref
      }
    }

    with {:ok, c} <- K8sClient.conn() do
      case K8s.Client.run(c, K8s.Client.create(manifest)) do
        {:ok, _} ->
          :ok

        {:error, %{"reason" => "AlreadyExists"}} ->
          {:error, "A plugin with this name already exists"}

        {:error, reason} ->
          {:error, inspect(reason)}
      end
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
