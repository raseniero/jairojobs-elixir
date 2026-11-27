defmodule JairojobsWeb.ListingLive.Index do
  @moduledoc """
  The public lists of jobs (spec 005): the home page, which lists the
  Published listings of every region (REQ-005-2), and each region's own list
  at `/jobs/<region slug>` (REQ-005-3). One LiveView, so choosing a region
  changes the list without loading a new page.

  The address is the state. Everything the page shows is read from it in
  `handle_params/3`, so an address opened again, or reached with the browser's
  back button, gives the same list.

  What may be listed is not decided here: `Jairojobs.Listings.list_public_listings/1`
  returns Published listings and nothing else (REQ-005-1). The page is the same
  for a visitor and for anyone logged in; only the menu differs.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Listings
  alias Jairojobs.Regions
  alias JairojobsWeb.Format
  alias JairojobsWeb.PublicAddress

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="jobs" class="space-y-3">
        <%!-- The choices are the active regions; a hidden one is never offered, though its
             own address still opens (REQ-005-3). The row scrolls inside itself when it is
             wider than the phone; the page does not. --%>
        <nav id="region-choices" aria-label="Regions" class="-mx-4 overflow-x-auto px-4">
          <ul class="flex w-max gap-2">
            <li :for={choice <- @regions}>
              <.region_choice
                id={"region-choice-#{choice.slug}"}
                path={PublicAddress.list_path(choice)}
                chosen={@region != nil and @region.id == choice.id}
                label={choice.name}
              />
            </li>
            <li>
              <.region_choice
                id="region-choice-all"
                path={PublicAddress.list_path(nil)}
                chosen={@region == nil}
                label="All regions"
              />
            </li>
          </ul>
        </nav>

        <%!-- A region's list names its region once, here, so its rows need not. The home
             page has no headline above the list (spec decision 7); its heading is for
             screen readers. --%>
        <h1 :if={@region} id="jobs-heading" class="text-[22px] font-bold break-words">
          Jobs in {@region.name}
        </h1>
        <h1 :if={!@region} id="jobs-heading" class="sr-only">Jobs in the Philippines</h1>

        <p :if={@total > 0} id="jobs-count" class="text-xs text-base-content/70">
          {count(@total, @region)} · newest first
        </p>

        <div
          :if={@total > 0}
          id="job-rows"
          phx-update="stream"
          class="divide-y divide-base-300 border-y border-base-300"
        >
          <.link
            :for={{dom_id, listing} <- @streams.listings}
            id={dom_id}
            href={PublicAddress.listing_path(listing)}
            class="block min-h-11 py-3 transition-colors hover:bg-base-200 focus-visible:bg-base-200"
          >
            <h2 class="text-[17px] leading-snug font-semibold break-words text-primary">
              {listing.title}
            </h2>
            <p class="mt-0.5 break-words">{listing.business_name} · {where(listing, @region)}</p>
            <p class="mt-1 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-sm text-base-content/70">
              <span class="font-semibold text-base-content">
                {Format.salary_range(listing.salary_min, listing.salary_max, :short)}
              </span>
              <span>{Format.time_ago(listing.published_at)}</span>
              <span class="rounded-full border border-success/40 px-2 text-xs font-semibold whitespace-nowrap text-success">
                ✓ Approved
              </span>
            </p>
          </.link>
        </div>

        <div :if={@total == 0} class="py-3">
          <p id="no-jobs" class="text-base-content/70">
            {if @region,
              do: "No jobs are listed in #{@region.name} yet.",
              else: "No jobs are listed yet."}
          </p>
          <%!-- A link of its own, not one inside a sentence, so it is 44 px tall. --%>
          <.link
            :if={@region}
            patch={PublicAddress.list_path(nil)}
            id="see-all-regions"
            class="inline-flex min-h-11 items-center text-primary hover:underline"
          >
            See all regions
          </.link>
        </div>

        <p id="trust-line" class="pt-2 text-xs text-base-content/70">
          Every listing shows salary and is checked by jairojobs before it is published.
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :chosen, :boolean, required: true

  # One region choice: a pill, 44 px tall. The chosen one is filled, and marked for
  # screen readers as well as by colour (spec 005, accessibility).
  defp region_choice(assigns) do
    ~H"""
    <.link
      patch={@path}
      id={@id}
      aria-current={@chosen && "page"}
      class={[
        "inline-flex min-h-11 items-center rounded-full border px-3.5 text-sm whitespace-nowrap",
        "transition-colors",
        @chosen && "border-primary bg-primary text-primary-content",
        !@chosen && "border-base-300 bg-base-100 hover:bg-base-200"
      ]}
    >
      {@label}
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:regions, Regions.list_active_regions())
     # A row's DOM id is made from its address, never from the listing's id, so no id
     # appears in a public page (plan decision 17). The two slugs are joined by a double
     # hyphen, which no slug contains, so two different addresses cannot make one id.
     |> stream_configure(:listings, dom_id: &"job-#{&1.region.slug}--#{&1.slug}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    region = region(socket.assigns.live_action, params)
    {listings, total} = Listings.list_public_listings(region: region)

    {:noreply,
     socket
     |> assign(:page_title, page_title(region))
     |> assign(:region, region)
     |> assign(:total, total)
     |> stream(:listings, listings, reset: true)}
  end

  # The home page is every region. A region's list is found by its slug, hidden or
  # not; an unknown slug raises, which is "not found" (REQ-005-3).
  defp region(:all, _params), do: nil
  defp region(:region, %{"region" => slug}), do: Regions.get_region_by_slug!(slug)

  defp page_title(nil), do: "Jobs in the Philippines, with the salary shown"
  defp page_title(region), do: "Jobs in #{region.name}"

  defp count(total, nil), do: jobs(total)
  defp count(total, region), do: "#{jobs(total)} in #{region.name}"

  defp jobs(1), do: "1 job"
  defp jobs(total), do: "#{total} jobs"

  # On the list of every region a row names the region after the area (REQ-005-2);
  # on a region's own list the heading has already named it (REQ-005-3).
  defp where(listing, nil), do: "#{listing.area}, #{listing.region.name}"
  defp where(listing, _region), do: listing.area
end
