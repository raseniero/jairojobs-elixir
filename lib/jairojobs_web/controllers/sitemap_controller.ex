defmodule JairojobsWeb.SitemapController do
  @moduledoc """
  `/sitemap.xml`: the public pages a search engine is told about (spec 005 —
  REQ-005-9).

  It lists the home page, the list of jobs of each active region, and the page
  of each Published listing, and nothing else. A hidden region's list is left
  out for as long as the region is hidden; its Published listings are listed
  like any others (spec decision 25). A Closed or Taken down listing is not
  listed: its address answers "gone". Private pages are behind log-in and are
  never here.

  Built on each request, with no cache: three short queries at the size the
  board has. The format allows 50,000 addresses in one file.

  It is read by machines, so its route goes through no pipeline: no session,
  no cookie, no layout.
  """
  use JairojobsWeb, :controller

  alias Jairojobs.Listings
  alias Jairojobs.Regions
  alias JairojobsWeb.PublicAddress

  def index(conn, _params) do
    lists =
      for region <- [nil | Regions.list_active_regions()],
          do: {PublicAddress.list_url(region), nil}

    # What is public is decided in the context: this returns Published listings only.
    listings =
      for address <- Listings.list_public_addresses(),
          do: {PublicAddress.listing_url(address), address.updated_at}

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml(lists ++ listings))
  end

  defp xml(pages) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.map(pages, &entry/1),
      "</urlset>\n"
    ]
    |> IO.iodata_to_binary()
  end

  # A list changes whenever a listing in it does, so it gives no date; a listing gives
  # the day it last changed.
  defp entry({address, nil}), do: ["<url><loc>", escape(address), "</loc></url>\n"]

  defp entry({address, %DateTime{} = changed}) do
    day = changed |> DateTime.to_date() |> Date.to_iso8601()
    ["<url><loc>", escape(address), "</loc><lastmod>", day, "</lastmod></url>\n"]
  end

  # Addresses are made of the site's own address and slugs, which hold nothing XML
  # reserves. Escaped all the same.
  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
