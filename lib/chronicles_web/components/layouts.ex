defmodule ChroniclesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ChroniclesWeb, :html

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
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :wide, :boolean, default: false, doc: "use the full width, for the game"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main class={["px-4 sm:px-6 lg:px-8", if(@wide, do: "py-6", else: "py-20")]}>
      <div class={["mx-auto space-y-4", if(@wide, do: "max-w-7xl", else: "max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The site header: navigation and the account menu.

  Rendered from the root layout, so it shows on every page.
  """
  attr :current_scope, :map, default: nil

  def site_header(assigns) do
    ~H"""
    <header class="navbar relative z-10 gap-4 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/stories"} class="text-lg font-semibold tracking-tight">
          Chronicles
        </.link>
      </div>
      <ul class="flex flex-none items-center gap-4">
        <li>
          <.button navigate={~p"/stories"} variant="ghost">{gettext("Stories")}</.button>
        </li>
        <li :if={@current_scope && @current_scope.user.role == :admin}>
          <.button navigate={~p"/admin/users"} variant="ghost">{gettext("Users")}</.button>
        </li>
        <%= if @current_scope do %>
          <li class="group">
            <button
              popovertarget="user-menu"
              class="flex cursor-pointer items-center gap-1 rounded-field px-2 py-1 text-sm transition [anchor-name:--user-menu] hover:bg-base-200"
            >
              {@current_scope.user.email}
              <.icon
                name="hero-chevron-down-micro"
                class="size-4 transition-transform group-has-[:popover-open]:rotate-180"
              />
            </button>
            <ul
              id="user-menu"
              popover
              class="inset-auto m-0 mt-2 min-w-40 rounded-box border border-base-300 bg-base-100 p-1 text-sm text-base-content shadow-lg [position-anchor:--user-menu] [position-area:bottom_span-left]"
            >
              <li>
                <.link
                  href={~p"/settings"}
                  class="block rounded-field px-3 py-2 hover:bg-base-200"
                >
                  {gettext("Settings")}
                </.link>
              </li>
              <li>
                <.link
                  href={~p"/account"}
                  class="block rounded-field px-3 py-2 hover:bg-base-200"
                >
                  {gettext("Account")}
                </.link>
              </li>
              <li>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="block rounded-field px-3 py-2 hover:bg-base-200"
                >
                  {gettext("Log out")}
                </.link>
              </li>
            </ul>
          </li>
        <% else %>
          <li>
            <.link href={~p"/users/register"}>{gettext("Sign up")}</.link>
          </li>
          <li>
            <.link href={~p"/users/log-in"}>{gettext("Log in")}</.link>
          </li>
          <li>
            <.link
              navigate={~p"/settings"}
              aria-label={gettext("Settings")}
              title={gettext("Settings")}
              class="flex opacity-70 transition hover:opacity-100"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </.link>
          </li>
        <% end %>
      </ul>
    </header>
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
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
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
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
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
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

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
