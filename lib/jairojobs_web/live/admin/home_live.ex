defmodule JairojobsWeb.Admin.HomeLive do
  @moduledoc """
  The admin area's home: a plain list of admin sections (spec 002, REQ-002-1).

  Regions is the first section; moderation (004) and stats (008) add theirs.
  """
  use JairojobsWeb, :live_view

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
              <span class="block text-sm text-base-content/70">{section.hint}</span>
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
    {:ok, assign(socket, page_title: "Admin", sections: sections())}
  end

  defp sections do
    [
      %{
        id: "regions",
        label: "Regions",
        hint: "The cities and areas the site serves.",
        href: "/admin/regions"
      }
    ]
  end
end
