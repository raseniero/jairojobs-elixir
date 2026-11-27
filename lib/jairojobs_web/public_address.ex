defmodule JairojobsWeb.PublicAddress do
  @moduledoc """
  The public addresses of spec 005, built in one place: `/` for the jobs of
  every region, `/jobs/<region slug>` for a region's (REQ-005-3), and
  `/jobs/<region slug>/<listing slug>` for a listing (REQ-005-6).

  The rows of the lists, the owner's and the Admin's view, the approval email,
  the sitemap and a page's own stated address all come here, so they cannot
  disagree. A listing's id is never part of a public address
  (constitution §4.8).
  """
  use JairojobsWeb, :verified_routes

  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions.Region

  @doc """
  The path of a list of jobs: a region's, or the home page for `nil`, which
  is the list of every region.
  """
  def list_path(nil), do: ~p"/"
  def list_path(%Region{slug: slug}), do: ~p"/jobs/#{slug}"

  @doc """
  The path of a listing's public page. The listing must have its slug, which
  it gets at approval, and its region loaded.
  """
  def listing_path(%Listing{slug: slug, region: %Region{slug: region_slug}}) when is_binary(slug),
    do: ~p"/jobs/#{region_slug}/#{slug}"

  @doc """
  The full address of a listing's public page, for an email, a share or a
  search engine.
  """
  def listing_url(%Listing{} = listing), do: url(~p"/jobs/#{listing.region.slug}/#{listing.slug}")
end
