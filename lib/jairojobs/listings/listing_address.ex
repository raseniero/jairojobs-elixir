defmodule Jairojobs.Listings.ListingAddress do
  @moduledoc """
  One public address a listing has or ever had: a slug in a region (spec 005,
  REQ-005-6).

  Every address is a row, the current one included, and rows are only ever
  inserted. The listing's current address is the row in the listing's own
  region; a row in any other region is an earlier address, which forwards.
  Because a row is never removed, an address is never given to another
  listing.

  Written only by `Jairojobs.Listings`: at approval, and when an Admin moves a
  Published listing to another region.
  """
  use Jairojobs.Schema

  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions.Region

  schema "listing_addresses" do
    field :slug, :string

    belongs_to :listing, Listing
    belongs_to :region, Region

    timestamps()
  end
end
