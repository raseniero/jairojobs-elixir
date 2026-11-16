defmodule JairojobsWeb.Admin.ListingLiveTest do
  @moduledoc """
  The Admin's moderation screens (spec 004): the Listings page with the
  approval queue, and the Admin view of one listing with its actions.
  """
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings

  defp log_in_admin(%{conn: conn}) do
    admin = admin_fixture()
    %{conn: log_in_user(conn, admin), admin: Scope.for_user(admin)}
  end

  # DOM ids of the listing rows, in the order they are rendered.
  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#admin-listings > li[id^='admin-listings-']")
    |> LazyHTML.attribute("id")
  end

  defp rows(listings), do: Enum.map(listings, &"admin-listings-#{&1.id}")

  defp text(view, selector), do: view |> element(selector) |> render() |> strip()

  defp strip(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end

  describe "access to the Listings page" do
    test "REQ-004-1: employer or candidate is refused", %{conn: conn} do
      for role <- ["employer", "candidate"] do
        conn = log_in_user(conn, user_fixture(role: role))

        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/listings")
        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-004-1: visitor is redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/listings")

      # ...and is brought back to the page they asked for after logging in (REQ-001-1)
      conn = get(conn, ~p"/admin/listings?status=live")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/admin/listings?status=live"
    end
  end

  describe "the Listings page" do
    setup :log_in_admin

    test "REQ-004-1: admin opens Listings", %{conn: conn} do
      {:ok, home, _html} = live(conn, ~p"/admin")

      {:ok, view, _html} =
        home |> element("#admin-section-listings") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "#admin-listings")
      # It opens on the approval queue.
      assert has_element?(view, "#filter-waiting[aria-current=page]")
      refute has_element?(view, "#filter-live[aria-current=page]")
    end

    test "REQ-004-2: longest-waiting first", %{conn: conn} do
      cashier = listing_in_status_fixture(employer_scope_fixture(), :pending)
      barista = listing_in_status_fixture(employer_scope_fixture(), :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      assert row_ids(view) == rows([cashier, barista])
    end

    test "REQ-004-2: what a row shows", %{conn: conn} do
      region = region_fixture(name: "Cebu #{System.unique_integer([:positive])}")
      employer = employer_scope_fixture(business_name: "Kape Isla")

      listing =
        listing_in_status_fixture(employer, :pending,
          title: "Cashier (weekends)",
          region_id: region.id,
          salary_min: 12_000,
          salary_max: 13_000
        )

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      row = text(view, "#admin-listings-#{listing.id}")
      assert row =~ "Cashier (weekends)"
      assert row =~ "Kape Isla"
      assert row =~ region.name
      assert row =~ "₱12,000–13,000/mo"
      assert text(view, "#listing-when-#{listing.id}") == "submitted just now"

      # The row leads to the listing's Admin view, remembering the list it came from.
      assert view |> element("#admin-listings-#{listing.id} a") |> render() =~
               "/admin/listings/#{listing.id}?from=waiting"
    end

    test "REQ-004-2: empty queue", %{conn: conn} do
      listing_in_status_fixture(employer_scope_fixture(), :published)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      assert row_ids(view) == []
      assert text(view, "#no-admin-listings") == "Nothing is waiting for approval."
    end

    test "REQ-004-2: drafts are not in the queue", %{conn: conn} do
      listing_fixture(employer_scope_fixture(), complete_listing_attrs())

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      assert row_ids(view) == []
    end

    test "REQ-004-2: a withdrawn listing leaves the queue", %{conn: conn} do
      employer = employer_scope_fixture()
      pending = listing_in_status_fixture(employer, :pending)
      {:ok, _draft} = Listings.withdraw_listing(employer, pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      assert row_ids(view) == []
    end

    test "REQ-004-2: my own listing is marked", %{conn: conn, admin: admin} do
      {:ok, _user} =
        Jairojobs.Accounts.update_business_details(admin, %{business_name: "Lutong Bahay"})

      admin = Scope.for_user(Jairojobs.Accounts.get_user!(admin.user.id))
      mine = listing_in_status_fixture(admin, :pending)
      theirs = listing_in_status_fixture(employer_scope_fixture(), :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      assert text(view, "#your-listing-#{mine.id}") == "Your listing"
      refute has_element?(view, "#your-listing-#{theirs.id}")
    end

    test "REQ-004-2: the Admin area shows how many are waiting", %{conn: conn} do
      for _ <- 1..2, do: listing_in_status_fixture(employer_scope_fixture(), :pending)
      listing_in_status_fixture(employer_scope_fixture(), :published)

      # ...on the Listings page, next to "Waiting for approval", whichever list is open.
      {:ok, view, _html} = live(conn, ~p"/admin/listings")
      assert text(view, "#waiting-count") == "(2)"
      assert text(view, "#filter-waiting") == "Waiting for approval (2)"

      {:ok, view, _html} = live(conn, ~p"/admin/listings?status=live")
      assert text(view, "#waiting-count") == "(2)"
    end

    test "REQ-004-3: choose a status", %{conn: conn} do
      waiting = listing_in_status_fixture(employer_scope_fixture(), :pending)
      older_live = listing_in_status_fixture(employer_scope_fixture(), :published)
      newer_live = listing_in_status_fixture(employer_scope_fixture(), :published)
      needs_changes = listing_in_status_fixture(employer_scope_fixture(), :rejected)
      taken_down = listing_in_status_fixture(employer_scope_fixture(), :taken_down)
      closed = listing_in_status_fixture(employer_scope_fixture(), :closed)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")
      assert row_ids(view) == rows([waiting])

      view |> element("#filter-live") |> render_click()
      assert_patch(view, ~p"/admin/listings?status=live")
      # Only the Live ones, the most recently changed first.
      assert row_ids(view) == rows([newer_live, older_live])
      assert has_element?(view, "#filter-live[aria-current=page]")
      assert text(view, "#listing-when-#{newer_live.id}") == "changed just now"

      for {slug, listing} <- [
            {"needs-changes", needs_changes},
            {"taken-down", taken_down},
            {"closed", closed}
          ] do
        view |> element("#filter-#{slug}") |> render_click()
        assert_patch(view, ~p"/admin/listings?status=#{slug}")
        assert row_ids(view) == rows([listing])
      end

      view |> element("#filter-waiting") |> render_click()
      assert_patch(view, ~p"/admin/listings")
      assert row_ids(view) == rows([waiting])
    end

    test "REQ-004-3: each status can be chosen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      labels =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#listing-filters a")
        |> Enum.map(&strip(LazyHTML.to_html(&1)))

      assert labels == [
               "Waiting for approval (0)",
               "Live",
               "Needs changes",
               "Taken down",
               "Closed"
             ]

      # There is no choice for Draft, and asking for it by address shows the queue.
      refute render(view) =~ "Draft"
      {:ok, view, _html} = live(conn, ~p"/admin/listings?status=draft")
      assert has_element?(view, "#filter-waiting[aria-current=page]")
    end

    test "REQ-004-3: nothing with that status", %{conn: conn} do
      for {slug, sentence} <- [
            {"live", "No listings are live."},
            {"needs-changes", "No listings need changes."},
            {"taken-down", "No listings have been taken down."},
            {"closed", "No listings are closed."}
          ] do
        {:ok, view, _html} = live(conn, ~p"/admin/listings?status=#{slug}")

        assert row_ids(view) == []
        assert text(view, "#no-admin-listings") == sentence
      end
    end

    test "REQ-004-3: a long list is shown in parts", %{conn: conn, admin: admin} do
      # An Admin owner has no limit on open listings.
      owner = admin_poster_scope_fixture()
      region = region_fixture()
      url = &"https://jairojobs.test/my/listings/#{&1.id}"

      live_listings =
        for _ <- 1..60 do
          pending = listing_in_status_fixture(owner, :pending, region_id: region.id)
          {:ok, live_listing, _email} = Listings.approve_listing(admin, pending, url)
          live_listing
        end

      newest_first = Enum.reverse(live_listings)

      {:ok, view, _html} = live(conn, ~p"/admin/listings?status=live")

      assert row_ids(view) == rows(Enum.take(newest_first, 50))
      assert has_element?(view, "#show-more")

      view |> element("#show-more") |> render_click()

      assert row_ids(view) == rows(newest_first)
      refute has_element?(view, "#show-more")
    end

    test "there is no Show more when everything fits", %{conn: conn} do
      listing_in_status_fixture(employer_scope_fixture(), :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings")

      refute has_element?(view, "#show-more")
    end

    test "an unknown status in the address shows the queue", %{conn: conn} do
      waiting = listing_in_status_fixture(employer_scope_fixture(), :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings?status=nonsense")

      assert row_ids(view) == rows([waiting])
      assert has_element?(view, "#filter-waiting[aria-current=page]")
    end
  end
end
