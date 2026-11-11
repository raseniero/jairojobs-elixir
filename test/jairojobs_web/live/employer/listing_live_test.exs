defmodule JairojobsWeb.Employer.ListingLiveTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Listings

  defp log_in_employer(%{conn: conn}) do
    scope = employer_scope_fixture(business_name: "Kape Isla")
    %{conn: log_in_user(conn, scope.user), scope: scope}
  end

  # DOM ids of the listing rows, in the order they are rendered.
  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-listings > li[id^='my-listings-']")
    |> LazyHTML.attribute("id")
  end

  defp text(view, selector), do: view |> element(selector) |> render() |> strip()

  defp strip(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.split() |> Enum.join(" ")
  end

  describe "access" do
    test "REQ-003-1: candidate is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: "candidate"))

      for path <- [~p"/my/listings"] do
        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-003-1: visitor is redirected to log in", %{conn: conn} do
      for path <- [~p"/my/listings"] do
        assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
      end

      # ...and is brought back to the page they asked for after logging in (REQ-001-1)
      conn = get(conn, ~p"/my/listings")
      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/my/listings"
    end
  end

  describe "my listings" do
    setup :log_in_employer

    test "REQ-003-1: employer opens My listings", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#nav-drawer-menu #nav-listings")
             |> LazyHTML.attribute("href") == ["/my/listings"]

      {:ok, view, _html} = live(conn, ~p"/my/listings")
      assert has_element?(view, "#my-listings")
    end

    test "REQ-003-13: see my listings", %{conn: conn, scope: scope} do
      region = region_fixture(name: "Davao #{System.unique_integer([:positive])}")

      older =
        listing_fixture(
          scope,
          complete_listing_attrs(title: "Barista (full-time)", region_id: region.id)
        )

      newer = listing_in_status_fixture(scope, :published, title: "Cashier (weekends)")
      {:ok, older} = Listings.update_listing(scope, older, %{schedule: "Mornings"})

      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert row_ids(view) == ["my-listings-#{older.id}", "my-listings-#{newer.id}"]

      row = text(view, "#my-listings-#{older.id}")
      assert row =~ "Barista (full-time)"
      assert row =~ "#{region.name} · ₱14,000–16,000/mo"
      assert text(view, "#listing-status-#{older.id}") == "Draft"
      assert text(view, "#listing-status-#{newer.id}") == "Live"
    end

    test "REQ-003-13: every status has its own label", %{conn: conn, scope: scope} do
      labels = %{
        draft: "Draft",
        pending: "Waiting for approval",
        published: "Live",
        rejected: "Needs changes",
        closed: "Closed",
        taken_down: "Taken down"
      }

      listings = for {status, _label} <- labels, do: listing_in_status_fixture(scope, status)

      {:ok, view, _html} = live(conn, ~p"/my/listings")

      for listing <- listings do
        assert text(view, "#listing-status-#{listing.id}") == labels[listing.status]
      end
    end

    test "REQ-003-13: unfinished draft in the list", %{conn: conn, scope: scope} do
      draft = listing_fixture(scope, %{title: "Dishwasher"})

      {:ok, view, _html} = live(conn, ~p"/my/listings")

      row = text(view, "#my-listings-#{draft.id}")
      assert row =~ "Dishwasher"
      assert row =~ "Not finished yet"
      refute row =~ "₱"
    end

    test "REQ-003-13: limit is shown", %{conn: conn, scope: scope} do
      listing_in_status_fixture(scope, :pending)
      listing_in_status_fixture(scope, :published)
      listing_in_status_fixture(scope, :closed)
      listing_fixture(scope)

      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert text(view, "#open-listings-count") == "2 of 3 open listings used"
    end

    test "REQ-003-13: no listings yet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert row_ids(view) == []
      assert has_element?(view, "#my-listings #no-listings")
      assert text(view, "#open-listings-count") == "0 of 3 open listings used"
    end

    test "REQ-003-14: my listings shows only mine", %{conn: conn, scope: scope} do
      mine = listing_in_status_fixture(scope, :published)
      other = employer_scope_fixture()
      theirs = listing_in_status_fixture(other, :published)
      listing_in_status_fixture(other, :pending)

      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert row_ids(view) == ["my-listings-#{mine.id}"]
      refute has_element?(view, "#my-listings-#{theirs.id}")
      assert text(view, "#open-listings-count") == "1 of 3 open listings used"
    end

    test "REQ-003-2: the business name is shown with a link to change it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert text(view, "#my-business") =~ "Kape Isla"

      assert {:ok, _view, _html} =
               view
               |> element("#edit-business")
               |> render_click()
               |> follow_redirect(conn, ~p"/my/business")
    end
  end

  describe "my listings as an admin" do
    test "REQ-003-12: admins are not shown the open-listings line", %{conn: conn} do
      scope = admin_poster_scope_fixture()
      listing = listing_in_status_fixture(scope, :pending)

      {:ok, view, _html} = conn |> log_in_user(scope.user) |> live(~p"/my/listings")

      assert row_ids(view) == ["my-listings-#{listing.id}"]
      refute has_element?(view, "#open-listings-count")
    end

    test "REQ-003-1: an admin reaches My listings from the admin area", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert {:ok, _view, _html} =
               view
               |> element("#admin-section-my-listings")
               |> render_click()
               |> follow_redirect(conn, ~p"/my/listings")
    end
  end
end
