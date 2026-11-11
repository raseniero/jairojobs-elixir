defmodule JairojobsWeb.Employer.ListingLive.Index do
  @moduledoc """
  "My listings": everything the current Employer (or Admin) has posted, with
  its status (spec 003 — REQ-003-13). Layout per `wireframe-posting`.
  """
  use JairojobsWeb, :live_view

  import JairojobsWeb.ListingComponents

  alias Jairojobs.Accounts
  alias Jairojobs.Listings
  alias JairojobsWeb.Format

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between gap-3">
        <h1 class="text-[22px] font-bold">My listings</h1>
        <.button navigate={~p"/my/listings/new"} id="post-a-job" variant="accent">
          <.icon name="hero-plus" class="size-5" /> Post a job
        </.button>
      </div>

      <p :if={@limit != :unlimited} id="open-listings-count" class="text-sm text-base-content/70">
        {@open_count} of {@limit} open listings used
      </p>

      <ul
        id="my-listings"
        phx-update="stream"
        class="divide-y divide-base-300 border-y border-base-300"
      >
        <li id="no-listings" class="hidden py-3 text-base-content/70 only:block">
          You haven't posted a job yet. Tap “Post a job” to write your first listing.
        </li>
        <li :for={{dom_id, listing} <- @streams.listings} id={dom_id}>
          <.link
            navigate={"/my/listings/#{listing.id}"}
            class="group flex min-h-11 items-center justify-between gap-3 py-3 transition-colors duration-150 hover:bg-base-200"
          >
            <span class="min-w-0">
              <span class="block text-[17px] font-semibold break-words text-primary group-hover:underline">
                {listing.title}
              </span>
              <span class="block text-sm text-base-content/70">{summary(listing)}</span>
            </span>
            <.status_badge listing={listing} />
          </.link>
        </li>
      </ul>

      <p id="my-business" class="text-sm text-base-content/70">
        <%= if @business_name do %>
          Posting as <span class="font-semibold text-base-content">{@business_name}</span>
          ·
          <.link navigate={~p"/my/business"} id="edit-business" class="text-primary hover:underline">
            Edit business details
          </.link>
        <% else %>
          <.link navigate={~p"/my/business"} id="edit-business" class="text-primary hover:underline">
            Add your business details
          </.link>
        <% end %>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "My listings")
     |> assign(:limit, Listings.open_listing_limit(scope))
     |> assign(:open_count, Listings.count_open_listings(scope))
     |> assign(:business_name, Accounts.business_details?(scope.user) && scope.user.business_name)
     |> stream_configure(:listings, dom_id: &"my-listings-#{&1.id}")
     |> stream(:listings, Listings.list_my_listings(scope))}
  end

  # Region and salary once both are filled in; otherwise the draft is not finished.
  defp summary(listing) do
    salary = Format.salary_range(listing.salary_min, listing.salary_max, :short)

    if listing.region && salary do
      "#{listing.region.name} · #{salary}"
    else
      "Not finished yet"
    end
  end
end
