defmodule JairojobsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JairojobsWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav_items, nav_items(assigns.current_scope))

    ~H"""
    <%!-- spec 001 — REQ-001-12 role-aware navigation per diagrams/wireframe-nav --%>
    <div class="drawer">
      <input id="nav-drawer" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex min-h-screen flex-col">
        <header class="border-b border-base-300 bg-base-100">
          <div class="mx-auto flex min-h-14 max-w-[720px] items-center gap-2 px-2 sm:px-4">
            <label
              for="nav-drawer"
              aria-label="Open menu"
              class="btn btn-ghost btn-square min-h-11 md:hidden"
            >
              <.icon name="hero-bars-3" class="size-6" />
            </label>

            <.wordmark class="px-2" />

            <nav id="nav-inline" aria-label="Main" class="ml-4 hidden flex-1 md:block">
              <ul class="menu menu-horizontal gap-1 p-0">
                <%!-- Log in / Log out live in the header button at md+ --%>
                <li :for={item <- @nav_items} :if={item.id not in [:login, :logout]}>
                  <.nav_link item={item} prefix="inline" />
                </li>
              </ul>
            </nav>

            <div class="ml-auto">
              <%= if @current_scope && @current_scope.user do %>
                <label
                  for="nav-drawer"
                  id="nav-header-account"
                  aria-label="Open account menu"
                  title={@current_scope.user.email}
                  class="btn btn-ghost btn-circle min-h-11 md:hidden"
                >
                  <.icon name="hero-user-circle" class="size-7 text-primary" />
                </label>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  id="nav-header-logout"
                  class="btn btn-ghost min-h-11 hidden border border-base-300 md:inline-flex"
                >
                  Log out
                </.link>
              <% else %>
                <.link
                  navigate={~p"/users/log-in"}
                  id="nav-header-login"
                  class="btn btn-ghost min-h-11 border border-base-300"
                >
                  Log in
                </.link>
              <% end %>
            </div>
          </div>
        </header>

        <main class="flex-1 px-4 py-8">
          <div class="mx-auto max-w-[720px] space-y-4">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>

      <div class="drawer-side z-40">
        <label for="nav-drawer" aria-label="Close menu" class="drawer-overlay"></label>
        <nav aria-label="Menu" class="min-h-full w-72 bg-base-100 p-4">
          <div class="mb-2 flex min-h-11 items-center justify-between px-2">
            <.wordmark id="wordmark-drawer" />
            <label for="nav-drawer" aria-label="Close menu" class="btn btn-ghost btn-square btn-sm">
              <.icon name="hero-x-mark" class="size-5" />
            </label>
          </div>
          <p
            :if={@current_scope && @current_scope.user}
            id="nav-drawer-account"
            class="truncate px-2 pb-2 text-sm text-base-content/70"
          >
            {@current_scope.user.email}
          </p>
          <ul id="nav-drawer-menu" class="menu w-full gap-1 p-0">
            <li
              :for={item <- @nav_items}
              class={item[:divider_before] && "mt-2 border-t border-base-300 pt-2"}
            >
              <.nav_link item={item} prefix="nav" />
            </li>
          </ul>
        </nav>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :item, :map, required: true
  attr :prefix, :string, required: true

  defp nav_link(%{item: %{id: :logout}} = assigns) do
    ~H"""
    <.link
      href={~p"/users/log-out"}
      method="delete"
      id={"#{@prefix}-logout"}
      class="min-h-11 items-center"
    >
      {@item.label}
    </.link>
    """
  end

  defp nav_link(assigns) do
    assigns =
      assign(assigns,
        dom_id: "#{assigns.prefix}-#{assigns.item.id |> to_string() |> String.replace("_", "-")}",
        class: [
          "min-h-11 items-center",
          assigns.item[:emphasis] == :cta && "btn btn-accent justify-center text-accent-content",
          assigns.item[:emphasis] == :strong && "font-semibold"
        ]
      )

    ~H"""
    <%= if @item[:placeholder] do %>
      <a href="#" id={@dom_id} data-placeholder={@item.placeholder} class={@class}>
        {@item.label}
      </a>
    <% else %>
      <.link navigate={@item.href} id={@dom_id} class={@class}>
        {@item.label}
      </.link>
    <% end %>
    """
  end

  @doc """
  Navigation items for the given scope (REQ-001-12, wireframe-nav).

  Items with `placeholder: "NNN"` link to `#` until that spec ships.
  """
  def nav_items(scope) do
    browse = %{id: :browse, label: "Browse jobs", href: ~p"/"}

    case Jairojobs.Accounts.Scope.role(scope) do
      nil ->
        [
          browse,
          %{
            id: :signup,
            label: "Sign up",
            href: ~p"/users/register",
            emphasis: :strong,
            divider_before: true
          },
          %{id: :login, label: "Log in", href: ~p"/users/log-in"}
        ]

      :candidate ->
        [
          browse,
          %{id: :applications, label: "My applications", href: "#", placeholder: "007"},
          %{id: :profile, label: "My profile", href: "#", placeholder: "006"}
        ] ++ account_items()

      :employer ->
        [
          browse,
          %{id: :listings, label: "My listings", href: ~p"/my/listings"},
          %{id: :post_job, label: "Post a job", href: "#", placeholder: "003", emphasis: :cta}
        ] ++ account_items()

      :admin ->
        [
          browse,
          %{id: :admin, label: "Admin", href: ~p"/admin", emphasis: :strong}
        ] ++ account_items()
    end
  end

  defp account_items do
    [
      %{id: :settings, label: "Settings", href: ~p"/users/settings", divider_before: true},
      %{id: :logout, label: "Log out", href: ~p"/users/log-out"}
    ]
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
  The text wordmark (design.md §4): `jairo` in text colour, `jobs` in primary.
  Links home. Placeholder until a real logo exists.
  """
  attr :id, :string, default: "wordmark"
  attr :class, :any, default: nil

  def wordmark(assigns) do
    ~H"""
    <.link
      navigate={~p"/"}
      id={@id}
      aria-label="jairojobs home"
      class={["inline-flex min-h-11 items-center text-lg font-bold tracking-tight", @class]}
    >
      <span class="text-base-content">jairo</span><span class="text-primary">jobs</span>
    </.link>
    """
  end
end
