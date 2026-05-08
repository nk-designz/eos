defmodule EosWeb.Router do
  use EosWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EosWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EosWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/brokers", BrokerLive.Index, :index
    live "/brokers/new", BrokerLive.Index, :new
    live "/plugins", PluginLive.Index, :index
    live "/plugins/new", PluginLive.Index, :new
    live "/plugins/:id", PluginLive.Show, :show
    live "/plugins/:id/edit", PluginLive.Show, :edit
  end

  scope "/webhooks", EosWeb do
    pipe_through :api

    post "/phaeton", NotificationController, :receive
  end

  if Application.compile_env(:eos, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EosWeb.Telemetry
    end
  end
end
