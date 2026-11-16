defmodule JairojobsWeb.Admin.HomeLive do
  @moduledoc """
  The admin area's home: a plain list of admin sections (spec 002, REQ-002-1).

  Listings (spec 004) comes first: moderation is the daily task, and its line
  says how many listings are waiting. Stats (008) add theirs later.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Listings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-[22px] font-bold">Admin</h1>

      <ul id="admin-sections" class="divide-y divide-base-300 border-y border-base-300">
        <li :for={section <- @sections}>
          <.link
            navigate={section.href}
            id={"admin-section-#{section.id}"}
            class="group flex min-h-11 items-center justify-between gap-3 py-3 transition-colors duration-150 hover:bg-base-200"
          >
            <span>
              <span class="block text-[17px] font-semibold text-primary group-hover:underline">
                {section.label}
              </span>
              <span id={section[:hint_id]} class="block text-sm text-base-content/70">
                {section.hint}
              </span>
            </span>
            <.icon name="hero-chevron-right" class="size-5 shrink-0 text-base-content/50" />
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    waiting = Listings.count_pending_listings(socket.assigns.current_scope)
    {:ok, assign(socket, page_title: "Admin", sections: sections(waiting))}
  end

  defp sections(waiting) do
    [
      # spec 004 — REQ-004-1, REQ-004-2: the approval queue, with how many are waiting.
      %{
        id: "listings",
        label: "Listings",
        hint: waiting_hint(waiting),
        hint_id: "admin-listings-waiting",
        href: ~p"/admin/listings"
      },
      %{
        id: "regions",
        label: "Regions",
        hint: "The cities and areas the site serves.",
        href: ~p"/admin/regions"
      },
      # spec 003 — REQ-003-1: Admins post through the same screens as Employers.
      %{
        id: "my-listings",
        label: "My listings",
        hint: "Listings you have posted yourself.",
        href: ~p"/my/listings"
      },
      %{
        id: "post-a-job",
        label: "Post a job",
        hint: "Add a listing yourself. It still needs approval.",
        href: ~p"/my/listings/new"
      }
    ]
  end

  defp waiting_hint(0), do: "Nothing waiting"
  defp waiting_hint(count), do: "#{count} waiting for approval"
end
