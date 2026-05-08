defmodule EosWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EosWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <header class="border-b border-base-200 bg-base-100/95 backdrop-blur-sm sticky top-0 z-50 shadow-sm">
        <nav class="flex items-center justify-between px-6 h-14 max-w-screen-xl mx-auto w-full">
          <div class="flex items-center gap-8">
            <.link navigate={~p"/"} class="flex items-center gap-2 group">
              <div class="size-7 rounded-lg bg-primary flex items-center justify-center shadow-sm group-hover:shadow-md transition-shadow">
                <.icon name="hero-bolt-micro" class="size-4 text-primary-content" />
              </div>
              <span class="font-bold text-base tracking-tight">EOS</span>
              <span class="text-base-content/40 text-xs hidden sm:block font-normal">IoT Agent</span>
            </.link>
            <div class="flex items-center gap-1">
              <.link
                navigate={~p"/"}
                class="px-3 py-1.5 rounded-lg text-sm font-medium text-base-content/70 hover:text-base-content hover:bg-base-200 transition-colors"
              >
                <.icon
                  name="hero-squares-2x2-micro"
                  class="size-4 inline-block mr-1 align-text-bottom"
                /> Dashboard
              </.link>
              <.link
                navigate={~p"/plugins"}
                class="px-3 py-1.5 rounded-lg text-sm font-medium text-base-content/70 hover:text-base-content hover:bg-base-200 transition-colors"
              >
                <.icon name="hero-cpu-chip-micro" class="size-4 inline-block mr-1 align-text-bottom" />
                Plugins
              </.link>
              <.link
                navigate={~p"/brokers"}
                class="px-3 py-1.5 rounded-lg text-sm font-medium text-base-content/70 hover:text-base-content hover:bg-base-200 transition-colors"
              >
                <.icon
                  name="hero-server-stack-micro"
                  class="size-4 inline-block mr-1 align-text-bottom"
                /> Brokers
              </.link>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <span class="hidden sm:flex items-center gap-1.5 text-xs text-base-content/50 bg-base-200 px-2.5 py-1 rounded-full">
              <span class="size-1.5 rounded-full bg-success animate-pulse inline-block"></span> Live
            </span>
            <.theme_toggle />
          </div>
        </nav>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
