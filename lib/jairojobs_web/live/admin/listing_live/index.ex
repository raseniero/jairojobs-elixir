defmodule JairojobsWeb.Admin.ListingLive.Index do
  @moduledoc """
  The Admin's Listings page (spec 004 — REQ-004-2, REQ-004-3): the approval
  queue first, and every other submitted listing one status at a time.

  The chosen status is part of the address (`?status=live`), so the browser's
  Back button returns to the same list. Drafts are never shown: they belong to
  their Employer alone.
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents, only: [status_label: 1]

  alias Jairojobs.Listings
  alias JairojobsWeb.Format

  @page_size 50

  # Address value, status, and what to say when no listing has that status.
  @filters [
    {"waiting", :pending, "Nothing is waiting for approval."},
    {"live", :published, "No listings are live."},
    {"needs-changes", :rejected, "No listings need changes."},
    {"taken-down", :taken_down, "No listings have been taken down."},
    {"closed", :closed, "No listings are closed."}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <nav aria-label="Breadcrumb" class="text-sm text-base-content/70">
        <.link navigate={~p"/admin"} id="breadcrumb-admin" class="text-primary hover:underline">
          Admin
        </.link>
        <span aria-hidden="true">▸</span>
        <span class="font-semibold text-base-content">Listings</span>
      </nav>

      <h1 class="text-[22px] font-bold">Listings</h1>

      <nav id="listing-filters" aria-label="Listing status" class="flex flex-wrap gap-2">
        <.link
          :for={{slug, status, _empty} <- @filters}
          patch={filter_path(slug)}
          id={"filter-#{slug}"}
          aria-current={slug == @slug && "page"}
          class={[
            "inline-flex min-h-11 items-center gap-1 rounded-full border px-4 text-sm",
            "transition-colors duration-150",
            if(slug == @slug,
              do: "border-primary bg-primary font-semibold text-primary-content",
              else: "border-base-300 text-primary hover:bg-base-200"
            )
          ]}
        >
          {status_label(status)}
          <span :if={status == :pending} id="waiting-count">({@waiting_count})</span>
        </.link>
      </nav>

      <ul
        id="admin-listings"
        phx-update="stream"
        class="divide-y divide-base-300 border-y border-base-300"
      >
        <li id="no-admin-listings" class="hidden py-3 text-base-content/70 only:block">
          {@empty_sentence}
        </li>
        <li :for={{dom_id, listing} <- @streams.listings} id={dom_id}>
          <.link
            navigate={"/admin/listings/#{listing.id}?from=#{@slug}"}
            class="group block min-h-11 py-3 transition-colors duration-150 hover:bg-base-200"
          >
            <span class="flex flex-wrap items-center gap-x-2">
              <span class="text-[17px] font-semibold break-words text-primary group-hover:underline">
                {listing.title}
              </span>
              <span
                :if={listing.user_id == @current_scope.user.id}
                id={"your-listing-#{listing.id}"}
                class="badge badge-ghost badge-sm rounded-full whitespace-nowrap"
              >
                Your listing
              </span>
            </span>
            <span class="block break-words">{listing.business_name} · {listing.region.name}</span>
            <span class="block text-sm text-base-content/70">
              <span class="font-semibold text-base-content">
                {Format.salary_range(listing.salary_min, listing.salary_max, :short)}
              </span>
              · <span id={"listing-when-#{listing.id}"}>{when_line(listing)}</span>
            </span>
          </.link>
        </li>
      </ul>

      <div :if={@more?}>
        <.button id="show-more" phx-click="show-more" phx-disable-with="Loading…">
          Show more
        </.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Listings", filters: @filters)
     |> stream_configure(:listings, dom_id: &"admin-listings-#{&1.id}")}
  end

  # An unknown or missing `status` is the approval queue.
  @impl true
  def handle_params(params, _uri, socket) do
    {slug, status, empty_sentence} =
      List.keyfind(@filters, params["status"], 0, hd(@filters))

    scope = socket.assigns.current_scope
    {listings, more?} = Listings.list_listings_for_moderation(scope, status, limit: @page_size)

    {:noreply,
     socket
     |> assign(slug: slug, status: status, empty_sentence: empty_sentence)
     |> assign(:waiting_count, Listings.count_pending_listings(scope))
     |> assign(shown: length(listings), more?: more?)
     |> stream(:listings, listings, reset: true)}
  end

  # The next 50, added below the ones already shown (plan decision 10).
  @impl true
  def handle_event("show-more", _params, socket) do
    %{current_scope: scope, status: status, shown: shown} = socket.assigns

    {listings, more?} =
      Listings.list_listings_for_moderation(scope, status, offset: shown, limit: @page_size)

    {:noreply,
     socket
     |> assign(shown: shown + length(listings), more?: more?)
     |> stream(:listings, listings)}
  end

  defp filter_path("waiting"), do: ~p"/admin/listings"
  defp filter_path(slug), do: ~p"/admin/listings?#{[status: slug]}"

  # The queue counts from the latest submission; the other lists from the last change.
  defp when_line(%{status: :pending, submitted_at: at}), do: "submitted #{Format.time_ago(at)}"
  defp when_line(%{updated_at: at}), do: "changed #{Format.time_ago(at)}"
end
