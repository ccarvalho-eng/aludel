defmodule Aludel.Web.Layouts do
  @moduledoc """
  Shared layouts for the embedded and standalone Aludel interfaces.
  """
  use Aludel.Web, :html

  alias Aludel.Web.Assets

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

  attr :current_path, :string, default: "", doc: "the current path for active link detection"
  attr :access, :atom, default: :all, values: [:all, :read_only]

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="aludel-header">
      <div class="aludel-header-inner">
        <nav class="aludel-nav">
          <.nav_link href={aludel_path("")} current_path={@current_path}>
            Home
          </.nav_link>
          <.nav_link href={aludel_path("prompts")} current_path={@current_path}>
            Prompts
          </.nav_link>
          <.nav_link href={aludel_path("suites")} current_path={@current_path}>
            Suites
          </.nav_link>
          <.nav_link href={aludel_path("datasets")} current_path={@current_path}>
            Datasets
          </.nav_link>
          <.nav_link href={aludel_path("providers")} current_path={@current_path}>
            Providers
          </.nav_link>
        </nav>
        <div style="margin-left: auto;">
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main class="aludel-main">
      <div class="aludel-container">
        <div
          :if={@access == :read_only}
          id="read-only-banner"
          role="status"
          class="mb-6 rounded-lg border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-base-content"
        >
          Read-only mode is active. Changes and model requests are disabled.
        </div>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
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
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
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
    <div
      class="theme-toggle"
      style="display: flex; gap: 4px; background-color: var(--bg-tertiary); border-radius: 8px; padding: 4px;"
    >
      <button
        class="theme-toggle-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System"
        style="padding: 6px 8px; border-radius: 6px; border: none; background: none; cursor: pointer; color: var(--text-secondary); transition: all 0.2s;"
      >
        <.icon name="hero-computer-desktop" class="size-4" />
      </button>

      <button
        class="theme-toggle-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light"
        style="padding: 6px 8px; border-radius: 6px; border: none; background: none; cursor: pointer; color: var(--text-secondary); transition: all 0.2s;"
      >
        <.icon name="hero-sun" class="size-4" />
      </button>

      <button
        class="theme-toggle-btn"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark"
        style="padding: 6px 8px; border-radius: 6px; border: none; background: none; cursor: pointer; color: var(--text-secondary); transition: all 0.2s;"
      >
        <.icon name="hero-moon" class="size-4" />
      </button>
    </div>
    """
  end

  # Private functions

  defp asset_path(conn, asset) when asset in [:css, :js] do
    hash = Assets.current_hash(asset)

    {_dash, _routing, meta} = conn.private.phoenix_live_view

    prefix = get_in(meta, [:extra, :session, Access.elem(2), Access.at(0)])

    path =
      case prefix do
        "/" -> "/#{asset}-#{hash}"
        "" -> "/#{asset}-#{hash}"
        _ -> "#{prefix}/#{asset}-#{hash}"
      end

    Phoenix.VerifiedRoutes.unverified_path(
      conn,
      conn.private.phoenix_router,
      path
    )
  end

  # Renders a navigation link with active state detection
  attr :href, :string, required: true
  attr :current_path, :string, default: ""
  slot :inner_block, required: true

  defp nav_link(assigns) do
    active =
      if assigns.current_path == assigns.href or
           String.starts_with?(assigns.current_path, assigns.href <> "/") do
        "active"
      else
        ""
      end

    assigns = assign(assigns, :active, active)

    ~H"""
    <.link navigate={@href} class={"aludel-nav-link #{@active}"}>
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
