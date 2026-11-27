defmodule JairojobsWeb.ListingController do
  @moduledoc """
  A listing's public page, `/jobs/<region>/<listing>` (spec 005 — REQ-005-5).

  `Jairojobs.Listings.resolve_public_address/2` decides what the address is;
  only a Published listing is ever shown (REQ-005-1).
  """
  use JairojobsWeb, :controller

  alias Jairojobs.Listings

  def show(conn, %{"region" => region_slug, "listing" => listing_slug}) do
    case Listings.resolve_public_address(region_slug, listing_slug) do
      {:ok, listing} ->
        conn
        |> assign(:page_title, listing.title)
        |> render(:show, listing: listing)

      # T13 gives an earlier address and a listing that is no longer listed their
      # own answers. Until then they are not found, like any other address.
      _moved_gone_or_never ->
        raise Phoenix.Router.NoRouteError, conn: conn, router: JairojobsWeb.Router
    end
  end
end
