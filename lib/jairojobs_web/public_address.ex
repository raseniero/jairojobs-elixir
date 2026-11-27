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

  `narrowed` is what narrows the list and is part of its address
  (REQ-005-4): `:search`, the words, and `:type`, as it is written in an
  address ("part-time"). `:shown` is how many rows the list is opened to,
  when that is more than the first 20. Whatever is `nil` is left out, so a
  list that is not narrowed has a plain address.
  """
  def list_path(region, narrowed \\ [])

  def list_path(nil, narrowed), do: ~p"/?#{query(narrowed)}"
  def list_path(%Region{slug: slug}, narrowed), do: ~p"/jobs/#{slug}?#{query(narrowed)}"

  defp query(narrowed) do
    for name <- [:search, :type, :shown], value = narrowed[name], do: {name, value}
  end

  @doc """
  The path of a listing's public page. The listing must have its slug, which
  it gets at approval, and its region loaded.
  """
  def listing_path(%Listing{slug: slug, region: %Region{slug: region_slug}}) when is_binary(slug),
    do: ~p"/jobs/#{region_slug}/#{slug}"

  # An address as `Jairojobs.Listings.resolve_public_address/2` gives it for a listing
  # that has moved: the two slugs, and nothing else of the listing.
  def listing_path(%{region_slug: region_slug, slug: slug}), do: ~p"/jobs/#{region_slug}/#{slug}"

  @doc """
  The full address of a listing's public page, for an email, a share or a
  search engine.
  """
  def listing_url(%Listing{} = listing), do: url(~p"/jobs/#{listing.region.slug}/#{listing.slug}")
end
