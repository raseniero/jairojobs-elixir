defmodule JairojobsWeb.ListingController do
  @moduledoc """
  A listing's public page, `/jobs/<region>/<listing>` (spec 005).

  `Jairojobs.Listings.resolve_public_address/2` decides what the address is,
  and this controller gives each answer the status a browser and a search
  engine understand:

    * the current address of a Published listing — the page (REQ-005-5)
    * an earlier address, from before an Admin moved the listing to another
      region — moved for good, to the current address (REQ-005-6)
    * the address of a listing that is Closed or Taken down — "gone", with a
      page that says so and shows nothing of the listing (REQ-005-7)
    * anything else — "not found", like any address the site does not have

  Only a Published listing is ever shown (REQ-005-1). A plain page, not a
  LiveView, because a LiveView cannot give these answers by itself (plan
  decision 1).
  """
  use JairojobsWeb, :controller

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings
  alias JairojobsWeb.PublicAddress
  alias JairojobsWeb.Seo

  def show(conn, %{"region" => region_slug, "listing" => listing_slug}) do
    case Listings.resolve_public_address(region_slug, listing_slug) do
      {:ok, listing} ->
        conn
        |> assign(:page_title, page_title(listing))
        |> assign(:seo, Seo.listing(listing))
        |> render(:show, listing: listing, manage: manage(conn, listing.id, listing.user_id))

      # Forwarded first, whatever the listing's status is now; its current address
      # says the rest. Anything added to the old address is dropped.
      {:moved, current} ->
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: PublicAddress.listing_path(current))

      # "Gone" tells a search engine to drop the page. The answer holds the region
      # and whose listing it was, and nothing of the listing itself.
      {:gone, %{region: region, id: id, user_id: owner_id}} ->
        conn
        |> put_status(:gone)
        |> assign(:page_title, "This job is no longer listed")
        |> assign(:seo, Seo.gone())
        |> render(:gone, region: region, manage: manage(conn, id, owner_id))

      :not_found ->
        raise Phoenix.Router.NoRouteError, conn: conn, router: JairojobsWeb.Router
    end
  end

  @doc """
  `/jobs` with nothing after it: forwards to the home page, the list of every
  region. People shorten addresses by hand.
  """
  def index(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: PublicAddress.list_path(nil))
  end

  # The links from a public page to the pages that manage the listing (REQ-005-10),
  # for whoever is logged in: to My listings for its owner, to the Admin view for an
  # Admin, both for an Admin who owns it, and none for anyone else.
  #
  # An owner who can no longer post (an Admin since demoted to Candidate) could not open
  # My listings, so is not offered it. Offering a link is a convenience; the pages the
  # links lead to check who is asking themselves (REQ-003-14, REQ-004-1).
  defp manage(conn, listing_id, owner_id) do
    scope = conn.assigns.current_scope
    owner? = Scope.poster?(scope) and scope.user.id == owner_id

    %{
      owner_path: if(owner?, do: ~p"/my/listings/#{listing_id}"),
      admin_path: if(Scope.admin?(scope), do: ~p"/admin/listings/#{listing_id}")
    }
  end

  # "Barista (full-time) — Kape Isla, Davao City"; the layout adds " | jairojobs"
  # (REQ-005-9). The salary is in the description, not here (spec decision 19).
  defp page_title(listing),
    do: "#{listing.title} — #{listing.business_name}, #{listing.region.name}"
end
