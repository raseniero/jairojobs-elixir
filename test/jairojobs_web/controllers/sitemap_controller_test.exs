defmodule JairojobsWeb.SitemapControllerTest do
  @moduledoc """
  The sitemap (spec 005 — REQ-005-9): the list of public pages a search engine
  is given. Each test is one request, as a search engine makes it.
  """
  use JairojobsWeb.ConnCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Listings
  alias Jairojobs.Regions

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  defp published(scope, admin, title, region, attrs \\ %{}) do
    attrs = Map.merge(%{title: title, region_id: region.id}, Map.new(attrs))
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    {:ok, listing} = Listings.submit_listing(scope, listing, &admin_url/1)
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url(), &public_url/1)
    flush_emails()
    listing
  end

  defp sitemap(conn), do: conn |> get("/sitemap.xml") |> response(200)

  # The addresses the sitemap lists, without the site's own address in front.
  defp listed(xml) do
    ~r{<loc>(.*?)</loc>}
    |> Regex.scan(xml, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&String.replace_prefix(&1, JairojobsWeb.Endpoint.url(), ""))
  end

  setup do
    %{
      owner: admin_poster_scope_fixture(business_name: "Kape Isla"),
      admin: admin_scope_fixture(),
      davao: region_fixture(name: "Davao City")
    }
  end

  test "REQ-005-9: The sitemap lists the public pages only",
       %{conn: conn, owner: owner, admin: admin, davao: davao} do
    # A Published listing, a Closed listing and a Draft; an active region and a hidden one.
    published(owner, admin, "Barista (full-time)", davao)

    {:ok, _closed} =
      Listings.close_listing(owner, published(owner, admin, "Cashier (weekends)", davao))

    listing_fixture(owner, complete_listing_attrs(title: "Only a draft", region_id: davao.id))
    region_fixture(name: "Baguio", active: false)

    # The home page, the active region's jobs and the Published listing; nothing else.
    assert conn |> sitemap() |> listed() == [
             "/",
             "/jobs/davao-city",
             "/jobs/davao-city/barista-full-time"
           ]
  end

  test "no other status is ever listed", %{conn: conn, owner: owner, admin: admin, davao: davao} do
    listing_in_status_fixture(owner, :pending, title: "A pending one", region_id: davao.id)
    listing_in_status_fixture(owner, :rejected, title: "A rejected one", region_id: davao.id)
    listing_in_status_fixture(owner, :taken_down, title: "A taken down one", region_id: davao.id)
    published(owner, admin, "The published one", davao)

    xml = sitemap(conn)

    assert listed(xml) == ["/", "/jobs/davao-city", "/jobs/davao-city/the-published-one"]
    refute xml =~ "taken-down"
    refute xml =~ "pending"
    refute xml =~ "rejected"
  end

  test "a hidden region's list is left out; its Published listing is not",
       %{conn: conn, owner: owner, admin: admin, davao: davao} do
    baguio = region_fixture(name: "Baguio")
    published(owner, admin, "Barista (full-time)", baguio)
    {:ok, hidden} = Regions.hide_region(admin, baguio)

    listed = conn |> sitemap() |> listed()

    refute "/jobs/baguio" in listed
    assert "/jobs/baguio/barista-full-time" in listed
    assert "/jobs/davao-city" in listed

    # Shown again, its list is back.
    {:ok, _shown} = Regions.show_region(admin, hidden)
    assert "/jobs/baguio" in (conn |> sitemap() |> listed())
  end

  test "a moved listing is listed at its current address only",
       %{conn: conn, owner: owner, admin: admin, davao: davao} do
    cebu = region_fixture(name: "Cebu")
    listing = published(owner, admin, "Barista (full-time)", davao)

    {:ok, _moved, _email} =
      Listings.update_listing_as_admin(admin, listing, %{region_id: cebu.id}, owner_url())

    listed = conn |> sitemap() |> listed()

    assert "/jobs/cebu/barista-full-time" in listed
    refute "/jobs/davao-city/barista-full-time" in listed
  end

  test "with nothing published it lists the home page and the active regions",
       %{conn: conn} do
    region_fixture(name: "Cebu")

    # A region with no jobs still has its list (REQ-005-3).
    assert conn |> sitemap() |> listed() == ["/", "/jobs/cebu", "/jobs/davao-city"]
  end

  test "every address is given in full, and every one of them opens",
       %{conn: conn, owner: owner, admin: admin, davao: davao} do
    published(owner, admin, "Barista (full-time)", davao)
    published(owner, admin, "Cashier (weekends)", region_fixture(name: "Cebu"))

    xml = sitemap(conn)
    full = ~r{<loc>(.*?)</loc>} |> Regex.scan(xml, capture: :all_but_first) |> List.flatten()

    assert length(full) == 5

    for address <- full do
      assert String.starts_with?(address, JairojobsWeb.Endpoint.url() <> "/")
      path = String.replace_prefix(address, JairojobsWeb.Endpoint.url(), "")

      assert conn |> get(path) |> html_response(200)
    end
  end

  test "private pages are never in it", %{conn: conn, owner: owner, admin: admin, davao: davao} do
    listing = published(owner, admin, "Barista (full-time)", davao)

    xml = sitemap(conn)

    for private <- ["/admin", "/my/", "/users/", listing.id, owner.user.id, owner.user.email] do
      refute xml =~ private
    end
  end

  test "a listing says when it last changed; lists do not",
       %{conn: conn, owner: owner, admin: admin, davao: davao} do
    listing = published(owner, admin, "Barista (full-time)", davao)
    changed = listing.updated_at |> DateTime.to_date() |> Date.to_iso8601()

    xml = sitemap(conn)

    assert xml =~
             "<loc>#{JairojobsWeb.Endpoint.url()}/jobs/davao-city/barista-full-time</loc>" <>
               "<lastmod>#{changed}</lastmod>"

    assert length(Regex.scan(~r/<lastmod>/, xml)) == 1
  end

  test "it is XML in the sitemap format, read by machines: no session, no cookie",
       %{conn: conn} do
    conn = get(conn, "/sitemap.xml")
    xml = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert String.starts_with?(xml, ~s(<?xml version="1.0" encoding="UTF-8"?>))
    assert xml =~ ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
    assert String.ends_with?(String.trim(xml), "</urlset>")

    # Every tag that opens closes.
    for tag <- ~w(url loc urlset) do
      assert length(Regex.scan(~r/<#{tag}[ >]/, xml)) == length(Regex.scan(~r{</#{tag}>}, xml))
    end

    assert get_resp_header(conn, "set-cookie") == []
    assert conn.resp_cookies == %{}
  end

  test "it is the same for anyone who asks", %{
    conn: conn,
    owner: owner,
    admin: admin,
    davao: davao
  } do
    published(owner, admin, "Barista (full-time)", davao)

    as_visitor = sitemap(conn)

    assert conn |> log_in_user(admin.user) |> sitemap() == as_visitor
    assert conn |> log_in_user(user_fixture(role: "candidate")) |> sitemap() == as_visitor
  end

  test "robots.txt tells search engines where the sitemap is", %{conn: conn} do
    robots = conn |> get("/robots.txt") |> response(200)

    assert robots =~ "\nSitemap: https://jairojobs.com/sitemap.xml\n"

    # Nothing is closed to them: private pages are behind log-in, not hidden by a rule.
    refute robots =~ ~r/^Disallow:/m
  end
end
