defmodule JairojobsWeb.Seo do
  @moduledoc """
  What a public page says about itself in its `<head>`, for the machines that
  read it: chat apps building a link preview (spec 005, REQ-005-8) and search
  engines (REQ-005-9).

  The functions here only build a map; `JairojobsWeb.Layouts.seo/1` writes the
  tags, in the root layout. A page that assigns no `:seo` gets none.

  Everything is taken from the listing as it is now, and only from what the
  public page itself shows.
  """

  alias Jairojobs.Listings.Listing
  alias JairojobsWeb.Format
  alias JairojobsWeb.PublicAddress

  @doc """
  The tags of a Published listing's public page.

  The preview a chat app shows is text only, since the site has no images:
  "Barista (full-time) — Kape Isla", then "₱14,000–16,000 / month · Matina,
  Davao City". The salary is in it because it is the first thing a job seeker
  asks (REQ-005-8).
  """
  def listing(%Listing{} = listing) do
    %{
      # A list, so the tags are written in this order every time.
      og: [
        title: "#{listing.title} — #{listing.business_name}",
        description:
          "#{Format.salary_range(listing.salary_min, listing.salary_max)} · " <>
            "#{listing.area}, #{listing.region.name}",
        url: PublicAddress.listing_url(listing),
        type: "website",
        site_name: "jairojobs"
      ]
    }
  end
end
