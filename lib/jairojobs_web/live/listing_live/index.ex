defmodule JairojobsWeb.ListingLive.Index do
  @moduledoc """
  The public lists of jobs (spec 005): the home page, which lists the
  Published listings of every region (REQ-005-2).

  The address is the state. Everything the page shows is read from it in
  `handle_params/3`, so an address opened again, or reached with the browser's
  back button, gives the same list.

  What may be listed is not decided here: `Jairojobs.Listings.list_public_listings/1`
  returns Published listings and nothing else (REQ-005-1). The page is the same
  for a visitor and for anyone logged in; only the menu differs.
  """
  use JairojobsWeb, :live_view

  alias Jairojobs.Listings
  alias JairojobsWeb.Format
  alias JairojobsWeb.PublicAddress

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="jobs" class="space-y-3">
        <%!-- No headline above the list (spec decision 7); this one is for screen readers. --%>
        <h1 id="jobs-heading" class="sr-only">Jobs in the Philippines</h1>

        <p :if={@total > 0} id="jobs-count" class="text-xs text-base-content/70">
          {count(@total)} · newest first
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
            <p class="mt-0.5 break-words">{listing.business_name} · {where(listing)}</p>
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

        <p :if={@total == 0} id="no-jobs" class="py-3 text-base-content/70">
          No jobs are listed yet.
        </p>

        <p id="trust-line" class="pt-2 text-xs text-base-content/70">
          Every listing shows salary and is checked by jairojobs before it is published.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # A row's DOM id is made from its address, never from the listing's id, so no id
    # appears in a public page (plan decision 17). The two slugs are joined by a double
    # hyphen, which no slug contains, so two different addresses cannot make one id.
    {:ok, stream_configure(socket, :listings, dom_id: &"job-#{&1.region.slug}--#{&1.slug}")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {listings, total} = Listings.list_public_listings()

    {:noreply,
     socket
     |> assign(:page_title, "Jobs in the Philippines, with the salary shown")
     |> assign(:total, total)
     |> stream(:listings, listings, reset: true)}
  end

  defp count(1), do: "1 job"
  defp count(total), do: "#{total} jobs"

  # On the list of every region a row names the region after the area (REQ-005-2).
  defp where(listing), do: "#{listing.area}, #{listing.region.name}"
end
