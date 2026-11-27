defmodule JairojobsWeb.ListingLive.IndexTest do
  @moduledoc """
  The public lists of jobs (spec 005): the home page, which lists every region,
  and each region's own list. Listings reach each status through the real
  context functions.
  """
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Listings

  @reason "Not suitable for the board as it is written."
  @trust_line "Every listing shows salary and is checked by jairojobs before it is published."

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  # A complete listing with `title` in `region`, approved: Published.
  defp published(scope, admin, title, region, attrs \\ %{}) do
    attrs = Map.merge(%{title: title, region_id: region.id}, Map.new(attrs))
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    {:ok, listing} = Listings.submit_listing(scope, listing, &admin_url/1)
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url())
    flush_emails()
    listing
  end

  # The titles on the rows, top to bottom.
  defp row_titles(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#job-rows > a h2")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  # The text of one element, with runs of white space made one space.
  defp text_of(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  setup do
    %{
      # An Admin owner has no limit on open listings (REQ-003-12).
      owner: admin_poster_scope_fixture(business_name: "Kape Isla"),
      admin: admin_scope_fixture(),
      davao: region_fixture(name: "Davao City"),
      cebu: region_fixture(name: "Cebu")
    }
  end

  describe "the home page (REQ-005-1)" do
    test "REQ-005-1: A Published listing is public without an account",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista (full-time)", davao)

      {:ok, view, html} = live(conn, ~p"/")

      assert row_titles(html) == ["Barista (full-time)"]
      assert has_element?(view, "#job-davao-city--barista-full-time")

      # The row leads to the listing's public page, which opens without an account too.
      assert {:error, {:redirect, %{to: "/jobs/davao-city/barista-full-time"}}} =
               view |> element("#job-davao-city--barista-full-time") |> render_click()

      assert conn |> get("/jobs/davao-city/barista-full-time") |> html_response(200) =~
               "Barista (full-time)"
    end

    test "REQ-005-1: Other statuses are on no public list",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing_fixture(owner, complete_listing_attrs(title: "A draft", region_id: davao.id))
      listing_in_status_fixture(owner, :pending, title: "A pending one", region_id: davao.id)
      listing_in_status_fixture(owner, :rejected, title: "A rejected one", region_id: davao.id)
      listing_in_status_fixture(owner, :closed, title: "A closed one", region_id: davao.id)

      listing_in_status_fixture(owner, :taken_down,
        title: "A taken down one",
        region_id: davao.id
      )

      published(owner, admin, "The published one", davao)

      {:ok, _view, html} = live(conn, ~p"/")

      assert row_titles(html) == ["The published one"]
      assert text_of(html, "#jobs-count") == "1 job · newest first"

      for hidden <- ["A draft", "A pending one", "A rejected one", "A closed one", "A taken down"] do
        refute html =~ hidden
      end
    end

    test "REQ-005-1: A taken down listing leaves the lists",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, _view, html} = live(conn, ~p"/")
      assert row_titles(html) == ["Barista (full-time)"]

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(admin, listing, %{reason: @reason}, owner_url())

      {:ok, view, html} = live(conn, ~p"/")

      assert row_titles(html) == []
      refute html =~ "Barista (full-time)"
      assert has_element?(view, "#no-jobs")
    end

    test "REQ-005-1: A hidden region does not hide a listing",
         %{conn: conn, owner: owner, admin: admin} do
      baguio = region_fixture(name: "Baguio")
      published(owner, admin, "Barista (full-time)", baguio)
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, baguio)

      {:ok, view, html} = live(conn, ~p"/")

      assert row_titles(html) == ["Barista (full-time)"]
      assert text_of(html, "#job-baguio--barista-full-time") =~ "Baguio"

      # And its public page opens.
      assert {:error, {:redirect, %{to: "/jobs/baguio/barista-full-time" = path}}} =
               view |> element("#job-baguio--barista-full-time") |> render_click()

      assert conn |> get(path) |> html_response(200) =~ "Barista (full-time)"
    end

    test "REQ-005-1: Logging in does not change the lists",
         %{conn: conn, admin: admin, davao: davao} do
      employer = employer_scope_fixture()
      published(employer, admin, "My published job", davao)
      listing_fixture(employer, complete_listing_attrs(title: "My draft", region_id: davao.id))
      published(admin_poster_scope_fixture(), admin, "Somebody else's job", davao)

      {:ok, _view, as_visitor} = live(conn, ~p"/")

      for user <- [employer.user, user_fixture(role: "candidate"), admin.user] do
        {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/")

        assert row_titles(html) == row_titles(as_visitor)
        assert Enum.sort(row_titles(html)) == ["My published job", "Somebody else's job"]
        refute html =~ "My draft"
      end
    end

    test "no listing's id is anywhere in the page",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "Barista (full-time)"
      refute html =~ listing.id
      refute html =~ owner.user.id
      refute html =~ owner.user.email
    end
  end

  describe "the home page lists the jobs of every region (REQ-005-2)" do
    test "REQ-005-2: Newest first", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      owner |> published(admin, "Cashier", davao) |> approved_ago(3, :hour)
      owner |> published(admin, "Barista", davao) |> approved_ago(20, :minute)

      {:ok, _view, html} = live(conn, ~p"/")

      assert row_titles(html) == ["Barista", "Cashier"]
    end

    test "REQ-005-2: What a row shows", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      owner
      |> published(admin, "Barista (full-time)", davao,
        area: "Matina",
        salary_min: 14_000,
        salary_max: 16_000
      )
      |> approved_ago(2, :hour)

      {:ok, view, html} = live(conn, ~p"/")

      row = text_of(html, "#job-davao-city--barista-full-time")

      assert row =~ "Barista (full-time)"
      assert row =~ "Kape Isla · Matina, Davao City"
      assert row =~ "₱14,000–16,000/mo"
      assert row =~ "2 h ago"
      assert row =~ "✓ Approved"

      # The whole row is one link, to the listing's public page.
      assert has_element?(
               view,
               ~s(a#job-davao-city--barista-full-time[href="/jobs/davao-city/barista-full-time"])
             )

      assert LazyHTML.from_fragment(html) |> LazyHTML.query("#job-rows a") |> Enum.count() == 1
    end

    test "a salary whose two ends are the same is written once",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista", davao, salary_min: 15_000, salary_max: 15_000)

      {:ok, _view, html} = live(conn, ~p"/")

      assert text_of(html, "#job-davao-city--barista") =~ "₱15,000/mo"
    end

    test "a listing approved more than a week ago shows the date",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = owner |> published(admin, "Barista", davao) |> approved_ago(10, :day)

      {:ok, _view, html} = live(conn, ~p"/")

      assert text_of(html, "#job-davao-city--barista") =~
               JairojobsWeb.Format.manila_date(listing.published_at)
    end

    test "REQ-005-2: How many jobs", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista", davao)

      {:ok, _view, html} = live(conn, ~p"/")
      assert text_of(html, "#jobs-count") == "1 job · newest first"

      published(owner, admin, "Cashier", davao)
      published(owner, admin, "Line cook", davao)

      {:ok, _view, html} = live(conn, ~p"/")
      assert text_of(html, "#jobs-count") == "3 jobs · newest first"
    end

    test "REQ-005-2: Nothing listed yet", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert text_of(html, "#no-jobs") == "No jobs are listed yet."
      assert row_titles(html) == []

      # An empty list has its message and no count line.
      refute has_element?(view, "#jobs-count")
      refute html =~ "coming soon"
    end

    test "REQ-005-2: A long list is shown in parts",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      for n <- 1..25 do
        owner |> published(admin, "Job number #{n}", davao) |> approved_ago(n, :hour)
      end

      {:ok, _view, html} = live(conn, ~p"/")

      assert row_titles(html) == Enum.map(1..20, &"Job number #{&1}")
      assert text_of(html, "#jobs-count") == "25 jobs · newest first"
    end

    test "REQ-005-2: The trust line is shown", %{
      conn: conn,
      owner: owner,
      admin: admin,
      davao: davao
    } do
      {:ok, _view, html} = live(conn, ~p"/")

      assert row_titles(html) == []
      assert text_of(html, "#trust-line") == @trust_line

      # And under a list that has rows.
      published(owner, admin, "Barista", davao)
      {:ok, _view, html} = live(conn, ~p"/")

      assert text_of(html, "#trust-line") == @trust_line
    end

    test "the page's title, and no headline above the list", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert page_title(view) =~ "Jobs in the Philippines, with the salary shown"

      # The first delivery carries the whole title, with the site's ending.
      assert conn |> get(~p"/") |> html_response(200) |> text_of("title") ==
               "Jobs in the Philippines, with the salary shown | jairojobs"

      # A heading for screen readers only (plan decision 14).
      assert text_of(html, "h1#jobs-heading.sr-only") == "Jobs in the Philippines"
    end

    test "the rows are in what is first delivered, before any live connection",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista (full-time)", davao)

      html = conn |> get(~p"/") |> html_response(200)

      assert row_titles(html) == ["Barista (full-time)"]
      assert text_of(html, "#trust-line") == @trust_line
    end
  end

  # These five were the tests of the home page when it was a controller (spec 001). The
  # home page is this LiveView now; what they prove has not changed.
  test "REQ-001-1: public pages render without login (home page)", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ ~s(id="jobs")
    refute get_session(conn, :user_token)
  end

  describe "REQ-001-12: navigation on the home page" do
    test "visitor sees Log in and Sign up", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="nav-login")
      assert html =~ ~s(id="nav-signup")
      refute html =~ ~s(id="nav-settings")
    end

    test "candidate sees applications, profile and settings", %{conn: conn} do
      html =
        conn |> log_in_user(user_fixture(role: "candidate")) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="nav-applications")
      assert html =~ ~s(id="nav-profile")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-admin")
    end

    test "employer sees listings, post a job and settings", %{conn: conn} do
      html =
        conn |> log_in_user(user_fixture(role: "employer")) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="nav-listings")
      assert html =~ ~s(id="nav-post-job")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-admin")
    end

    test "admin additionally sees Admin", %{conn: conn} do
      html = conn |> log_in_user(admin_fixture()) |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="nav-admin")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-applications")
      refute html =~ ~s(id="nav-listings")
    end
  end

  describe "the listing's address, until its page is finished (T12, T13)" do
    test "anything that is not the current address of a Published listing is not found",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      for path <- [
            "/jobs/davao-city/no-such-job",
            "/jobs/atlantis/barista-full-time",
            "/jobs/davao-city/#{listing.id}"
          ] do
        assert conn |> get(path) |> response(404) == "Not Found"
      end
    end
  end
end
