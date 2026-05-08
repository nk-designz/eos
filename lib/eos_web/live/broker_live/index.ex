defmodule EosWeb.BrokerLive.Index do
  @moduledoc """
  LiveView for listing and managing Context Broker CRDs.
  """

  use EosWeb, :live_view

  require Logger

  alias Eos.K8s.Client, as: K8sClient

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:current_scope, fn -> nil end)
      |> assign(:page_title, "Context Brokers")
      |> assign(:form_open, false)
      |> assign(:form_error, nil)
      |> load_brokers()

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"action" => "new"}, _uri, socket) do
    form =
      to_form(
        %{
          "name" => "",
          "url" => "",
          "tenant" => "default",
          "token" => ""
        },
        as: :broker
      )

    {:noreply, assign(socket, form_open: true, form: form, form_error: nil)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, form_open: false)}
  end

  @impl true
  def handle_event("open_form", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/brokers?action=new")}
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/brokers")}
  end

  def handle_event("validate", %{"broker" => params}, socket) do
    form = to_form(params, as: :broker)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"broker" => params}, socket) do
    name = String.trim(params["name"])
    url = String.trim(params["url"])
    tenant = String.trim(params["tenant"])
    token = String.trim(params["token"])

    cond do
      name == "" ->
        {:noreply, assign(socket, form_error: "Name is required")}

      not Regex.match?(~r/^[a-z0-9][a-z0-9\-]*[a-z0-9]$|^[a-z0-9]$/, name) ->
        {:noreply, assign(socket, form_error: "Name must be lowercase alphanumeric and hyphens")}

      url == "" ->
        {:noreply, assign(socket, form_error: "URL is required")}

      token == "" ->
        {:noreply, assign(socket, form_error: "Bearer token is required")}

      true ->
        create_broker(socket, name, url, tenant, token)
    end
  end

  def handle_event("delete", %{"name" => name}, socket) do
    secret_name = "eos-broker-#{name}-token"

    case K8sClient.delete_broker(name) do
      {:ok, _} ->
        K8sClient.delete_secret(secret_name)
        {:noreply, socket |> put_flash(:info, "Broker '#{name}' deleted") |> load_brokers()}

      {:error, reason} ->
        Logger.error("[BrokerLive] Delete broker #{name} failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Could not delete broker: #{inspect(reason)}")}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp create_broker(socket, name, url, tenant, token) do
    secret_name = "eos-broker-#{name}-token"

    with {:ok, _} <- K8sClient.create_secret(secret_name, %{"token" => token}),
         {:ok, _} <- K8sClient.create_broker(broker_manifest(name, url, tenant, secret_name)) do
      socket =
        socket
        |> put_flash(:info, "Broker '#{name}' created")
        |> load_brokers()
        |> push_patch(to: ~p"/brokers")

      {:noreply, socket}
    else
      {:error, %{"reason" => "AlreadyExists"}} ->
        {:noreply, assign(socket, form_error: "A broker with this name already exists")}

      {:error, reason} ->
        Logger.error("[BrokerLive] Create broker #{name} failed: #{inspect(reason)}")
        {:noreply, assign(socket, form_error: "Failed to create broker: #{inspect(reason)}")}
    end
  end

  defp broker_manifest(name, url, tenant, secret_name) do
    %{
      "apiVersion" => "eos.io/v1alpha1",
      "kind" => "Broker",
      "metadata" => %{
        "name" => name,
        "namespace" => K8sClient.namespace()
      },
      "spec" => %{
        "url" => url,
        "tenant" => tenant,
        "tokenSecretRef" => %{
          "name" => secret_name,
          "key" => "token"
        }
      }
    }
  end

  defp load_brokers(socket) do
    brokers =
      case K8sClient.list_brokers() do
        {:ok, %{"items" => items}} -> items
        _ -> []
      end

    assign(socket, :brokers, brokers)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto px-4 py-10">
        <%!-- Header --%>
        <div class="flex items-start justify-between mb-8">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Context Brokers</h1>
            <p class="mt-1 text-sm text-base-content/50">
              Manage NGSI-LD broker connections. Plugins reference a broker by name.
            </p>
          </div>
          <button
            id="open-broker-form"
            phx-click="open_form"
            class="flex items-center gap-2 px-4 py-2 bg-primary text-primary-content text-sm font-medium rounded-lg hover:opacity-90 active:scale-95 transition-all"
          >
            <.icon name="hero-plus" class="w-4 h-4" /> New Broker
          </button>
        </div>

        <%!-- Create form — slide-in modal --%>
        <%= if @form_open do %>
          <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm">
            <div class="bg-base-100 border border-base-300 rounded-2xl shadow-2xl w-full max-w-md mx-4 p-6">
              <div class="flex items-center gap-2.5 mb-5">
                  <div class="flex items-center gap-2.5">
                    <div class="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                      <.icon name="hero-server-stack" class="w-4 h-4 text-primary" />
                    </div>
                    <h2 class="text-base font-semibold text-base-content">New Context Broker</h2>
                  </div>
                  <button
                    phx-click="close_form"
                    class="p-1 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
                  >
                    <.icon name="hero-x-mark" class="w-5 h-5" />
                  </button>
                </div>

                <%= if @form_error do %>
                  <div class="mb-4 flex items-start gap-2 p-3 rounded-lg bg-error/10 border border-error/20 text-sm text-error">
                    <.icon name="hero-exclamation-circle" class="w-4 h-4 flex-shrink-0 mt-0.5" />
                    {@form_error}
                  </div>
                <% end %>

                <.form
                  for={@form}
                  id="broker-form"
                  phx-change="validate"
                  phx-submit="save"
                  class="space-y-4"
                >
                  <.input
                    field={@form[:name]}
                    type="text"
                    label="Broker name"
                    placeholder="phaeton-production"
                  />
                  <.input
                    field={@form[:url]}
                    type="text"
                    label="Broker URL"
                    placeholder="https://broker.example.com"
                  />
                  <.input
                    field={@form[:tenant]}
                    type="text"
                    label="Default tenant"
                    placeholder="default"
                  />
                  <.input
                    field={@form[:token]}
                    type="password"
                    label="Bearer token"
                    placeholder="phtn_…"
                  />

                  <div class="flex justify-end gap-3 pt-2 border-t border-base-200">
                    <button
                      type="button"
                      phx-click="close_form"
                      class="px-4 py-2 text-sm font-medium text-base-content/70 bg-base-200 rounded-lg hover:bg-base-300 transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      class="px-4 py-2 text-sm font-medium bg-primary text-primary-content rounded-lg hover:opacity-90 transition-opacity"
                    >
                      Create Broker
                    </button>
                  </div>
                </.form>
            </div>
          </div>
        <% end %>

        <%!-- Broker list --%>
        <%= if @brokers == [] do %>
          <div class="flex flex-col items-center justify-center py-24 border-2 border-dashed border-base-300 rounded-2xl">
            <div class="w-14 h-14 rounded-2xl bg-base-200 flex items-center justify-center mb-4">
              <.icon name="hero-server-stack" class="w-7 h-7 text-base-content/30" />
            </div>
            <p class="font-medium text-base-content/70">No brokers configured</p>
            <p class="text-sm text-base-content/40 mt-1 mb-5">
              Add a context broker to start routing plugin data.
            </p>
            <button
              phx-click="open_form"
              class="flex items-center gap-2 px-4 py-2 text-sm font-medium bg-primary text-primary-content rounded-lg hover:opacity-90 transition-opacity"
            >
              <.icon name="hero-plus" class="w-4 h-4" /> Add first broker
            </button>
          </div>
        <% else %>
          <div class="grid gap-3">
            <%= for broker <- @brokers do %>
              <% name = get_in(broker, ["metadata", "name"]) %>
              <% url = get_in(broker, ["spec", "url"]) %>
              <% tenant = get_in(broker, ["spec", "tenant"]) %>
              <% secret_name = get_in(broker, ["spec", "tokenSecretRef", "name"]) %>
              <% phase = get_in(broker, ["status", "phase"]) %>
              <div
                id={"broker-#{name}"}
                class="group flex items-center justify-between px-5 py-4 bg-base-100 border border-base-300 rounded-xl hover:border-primary/30 hover:shadow-sm transition-all"
              >
                <div class="flex items-center gap-4 min-w-0">
                  <div class="flex-shrink-0 w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                    <.icon name="hero-server" class="w-5 h-5 text-primary" />
                  </div>
                  <div class="min-w-0">
                    <div class="flex items-center gap-2">
                      <p class="font-semibold text-base-content truncate">{name}</p>
                      <%= if phase do %>
                        <span class={[
                          "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                          phase == "Ready" && "bg-success/15 text-success",
                          phase == "Error" && "bg-error/15 text-error",
                          is_nil(phase) || phase not in ["Ready", "Error"] && "bg-base-200 text-base-content/50"
                        ]}>
                          {phase}
                        </span>
                      <% end %>
                    </div>
                    <p class="text-sm text-base-content/50 truncate font-mono">{url}</p>
                    <div class="flex items-center gap-4 mt-1.5">
                      <span class="inline-flex items-center gap-1 text-xs text-base-content/40">
                        <.icon name="hero-building-office" class="w-3 h-3" /> {tenant}
                      </span>
                      <span class="inline-flex items-center gap-1 text-xs text-base-content/40">
                        <.icon name="hero-key" class="w-3 h-3" /> {secret_name}
                      </span>
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-1 flex-shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
                  <a
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="p-2 rounded-lg text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
                    title="Open broker"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                  </a>
                  <button
                    phx-click="delete"
                    phx-value-name={name}
                    data-confirm={"Delete broker '#{name}'? This cannot be undone."}
                    class="p-2 rounded-lg text-base-content/40 hover:text-error hover:bg-error/10 transition-colors"
                    title="Delete broker"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
