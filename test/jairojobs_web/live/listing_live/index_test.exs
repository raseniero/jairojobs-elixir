defmodule JairojobsWeb.ListingLive.IndexTest do
  @moduledoc """
  The public lists of jobs (spec 005): the home page, which lists every region,
  and each region's own list. Listings reach each status through the real
  context functions.
  """
  # Not async (constitution §3.5): region names and slugs are unique, and these tests use
  # fixed region names ("Davao City", "Cebu") because the public addresses they check are
  # made from the region's slug. Concurrent sandbox transactions inserting the same names
  # wait on each other's unique-index entries and can deadlock.
  use JairojobsWeb.ConnCase, async: false

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
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url(), &public_url/1)
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

      {:ok, view, html} = live(conn, ~p"/")

      assert row_titles(html) == Enum.map(1..20, &"Job number #{&1}")
      assert text_of(html, "#jobs-count") == "25 jobs · newest first"

      # And I can ask for more.
      assert text_of(html, "#show-more") == "Show more"
      html = view |> element("#show-more") |> render_click()

      assert row_titles(html) == Enum.map(1..25, &"Job number #{&1}")
      refute has_element?(view, "#show-more")
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

  describe "jobs in one region (REQ-005-3)" do
    # The region choices, left to right: `{text, chosen?}`.
    defp region_choices(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#region-choices a")
      |> Enum.map(fn choice ->
        {choice |> LazyHTML.text() |> String.trim(),
         LazyHTML.attribute(choice, "aria-current") == ["page"]}
      end)
    end

    test "REQ-005-3: Choose a region",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      published(owner, admin, "Barista", davao)
      published(owner, admin, "Cashier", davao)
      published(owner, admin, "Line cook", cebu)

      {:ok, view, html} = live(conn, ~p"/")
      assert length(row_titles(html)) == 3

      html = view |> element("#region-choice-davao-city") |> render_click()

      assert_patch(view, "/jobs/davao-city")
      assert Enum.sort(row_titles(html)) == ["Barista", "Cashier"]
      assert text_of(html, "#jobs-count") == "2 jobs in Davao City · newest first"
      assert text_of(html, "h1#jobs-heading") == "Jobs in Davao City"
      assert {"Davao City", true} in region_choices(html)
    end

    test "one job in a region is counted as \"1 job\"",
         %{conn: conn, owner: owner, admin: admin, cebu: cebu} do
      published(owner, admin, "Line cook", cebu)

      {:ok, _view, html} = live(conn, ~p"/jobs/cebu")

      assert text_of(html, "#jobs-count") == "1 job in Cebu · newest first"
    end

    test "REQ-005-3: Rows do not repeat the region",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista (full-time)", davao, area: "Matina")

      {:ok, _view, html} = live(conn, ~p"/jobs/davao-city")

      row = text_of(html, "#job-davao-city--barista-full-time")

      assert row =~ "Kape Isla · Matina"
      refute row =~ "Davao City"

      # The region is named once, in the heading.
      assert text_of(html, "h1#jobs-heading") == "Jobs in Davao City"
      refute html =~ "sr-only"
    end

    test "REQ-005-3: The choices are the active regions", %{conn: conn, admin: admin} do
      region_fixture(name: "Baguio", active: false)
      zamboanga = region_fixture(name: "Zamboanga")

      {:ok, _view, html} = live(conn, ~p"/")

      # "All regions" first, then the active regions in alphabetical order. On the home
      # page "All regions" is the one chosen, so the chosen choice is the first thing seen.
      assert region_choices(html) == [
               {"All regions", true},
               {"Cebu", false},
               {"Davao City", false},
               {"Zamboanga", false}
             ]

      refute html =~ "Baguio"

      # A region with no jobs is offered all the same; one that is hidden stops being.
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, zamboanga)
      {:ok, _view, html} = live(conn, ~p"/jobs/cebu")

      assert region_choices(html) == [
               {"All regions", false},
               {"Cebu", true},
               {"Davao City", false}
             ]
    end

    test "REQ-005-3: A region with no jobs",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista", davao)

      {:ok, view, html} = live(conn, ~p"/jobs/cebu")

      assert text_of(html, "#no-jobs") == "No jobs are listed in Cebu yet."
      assert text_of(html, "#see-all-regions") == "See all regions"
      assert row_titles(html) == []
      refute has_element?(view, "#jobs-count")
      assert text_of(html, "#trust-line") == @trust_line

      # And a way to all regions.
      view |> element("#see-all-regions") |> render_click()
      assert_patch(view, "/")
      assert row_titles(render(view)) == ["Barista"]
    end

    test "REQ-005-3: A hidden region still opens by its address",
         %{conn: conn, owner: owner, admin: admin} do
      baguio = region_fixture(name: "Baguio")
      published(owner, admin, "Barista (full-time)", baguio)
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, baguio)

      {:ok, _view, html} = live(conn, ~p"/jobs/baguio")

      assert text_of(html, "h1#jobs-heading") == "Jobs in Baguio"
      assert row_titles(html) == ["Barista (full-time)"]
      assert text_of(html, "#jobs-count") == "1 job in Baguio · newest first"

      # It is not offered, so no region choice is marked as chosen.
      assert region_choices(html) == [
               {"All regions", false},
               {"Cebu", false},
               {"Davao City", false}
             ]
    end

    test "REQ-005-3: Unknown region", %{conn: conn} do
      assert_error_sent :not_found, fn -> get(conn, "/jobs/atlantis") end
      assert_raise Ecto.NoResultsError, fn -> live(conn, "/jobs/atlantis") end

      # Not a slug at all.
      assert_error_sent :not_found, fn -> get(conn, "/jobs/Davao%20City") end
    end

    test "REQ-005-3: Back to all regions",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      published(owner, admin, "Barista", davao)
      published(owner, admin, "Line cook", cebu)

      {:ok, view, html} = live(conn, ~p"/jobs/davao-city")
      assert row_titles(html) == ["Barista"]

      html = view |> element("#region-choice-all") |> render_click()

      assert_patch(view, "/")
      assert Enum.sort(row_titles(html)) == ["Barista", "Line cook"]
      assert {"All regions", true} in region_choices(html)

      # On the home page the rows name the region again.
      assert text_of(html, "#job-cebu--line-cook") =~ "Matina, Cebu"
    end

    test "from one region straight to another",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      published(owner, admin, "Barista", davao)
      published(owner, admin, "Line cook", cebu)

      {:ok, view, _html} = live(conn, ~p"/jobs/davao-city")
      html = view |> element("#region-choice-cebu") |> render_click()

      assert_patch(view, "/jobs/cebu")
      assert row_titles(html) == ["Line cook"]

      assert region_choices(html) == [
               {"All regions", false},
               {"Cebu", true},
               {"Davao City", false}
             ]
    end

    test "a renamed region keeps its address, and its new name is shown",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista", davao)
      {:ok, _renamed} = Jairojobs.Regions.rename_region(admin, davao, %{name: "Davao"})

      {:ok, _view, html} = live(conn, ~p"/jobs/davao-city")

      assert text_of(html, "h1#jobs-heading") == "Jobs in Davao"
      assert row_titles(html) == ["Barista"]
    end

    test "REQ-005-9: A region's jobs have their own title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/jobs/davao-city")
      assert page_title(view) =~ "Jobs in Davao City"

      # As a search engine reads it: the first delivery, with the site's ending.
      assert conn |> get(~p"/jobs/davao-city") |> html_response(200) |> text_of("title") ==
               "Jobs in Davao City | jairojobs"

      # The title follows the region when the visitor chooses another.
      view |> element("#region-choice-cebu") |> render_click()
      assert page_title(view) =~ "Jobs in Cebu"
    end

    test "a region's list needs no account, and every choice is a real link",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista", davao)

      html = conn |> get(~p"/jobs/davao-city") |> html_response(200)

      assert row_titles(html) == ["Barista"]

      hrefs =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#region-choices a")
        |> LazyHTML.attribute("href")

      assert hrefs == ["/", "/jobs/cebu", "/jobs/davao-city"]
    end
  end

  describe "search and filter by type (REQ-005-4)" do
    # The fixtures' usual "About the job" mentions a barista; these listings name nothing
    # a test searches for.
    @plain "A steady job with a friendly team in a busy neighbourhood shop."

    defp plain(scope, admin, title, region, attrs \\ %{}),
      do:
        published(scope, admin, title, region, Map.merge(%{description: @plain}, Map.new(attrs)))

    defp search_for(view, words),
      do: view |> form("#search-form", %{search: words}) |> render_submit()

    # Choosing a type applies at once, as a browser sends it: with the field that changed.
    defp choose_type(view, type, more \\ %{}) do
      view
      |> form("#search-form", Map.merge(%{type: type}, more))
      |> render_change(%{"_target" => ["type"]})
    end

    # What the search form holds: `{words, type}`.
    defp form_values(html) do
      doc = LazyHTML.from_fragment(html)

      {doc |> LazyHTML.query("#search-words") |> LazyHTML.attribute("value") |> List.first(),
       doc
       |> LazyHTML.query("#search-type option[selected]")
       |> LazyHTML.attribute("value")
       |> List.first()}
    end

    test "REQ-005-4: Search by a word in the title",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista (full-time)", davao)
      plain(owner, admin, "Cashier", davao)

      {:ok, view, _html} = live(conn, ~p"/")
      html = search_for(view, "barista")

      assert_patch(view, "/?search=barista")
      assert row_titles(html) == ["Barista (full-time)"]
      refute html =~ "Cashier"
      assert text_of(html, "#jobs-count") == "1 job · newest first"
      assert {"barista", _any} = form_values(html)
    end

    test "REQ-005-4: Filter by type", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "A full-time job", davao, employment_type: :full_time)
      plain(owner, admin, "A part-time job", davao, employment_type: :part_time)

      {:ok, view, html} = live(conn, ~p"/")

      # The types of REQ-003-4, after "Any type".
      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#search-type option")
             |> Enum.map(&{LazyHTML.attribute(&1, "value"), String.trim(LazyHTML.text(&1))}) == [
               {[""], "Any type"},
               {["full-time"], "Full-time"},
               {["part-time"], "Part-time"},
               {["contract"], "Contract"},
               {["temporary"], "Temporary"},
               {["internship"], "Internship"}
             ]

      html = choose_type(view, "part-time")

      assert_patch(view, "/?type=part-time")
      assert row_titles(html) == ["A part-time job"]
      assert {_no_words, "part-time"} = form_values(html)

      # Back to any type.
      html = choose_type(view, "")
      assert_patch(view, "/")
      assert length(row_titles(html)) == 2
    end

    test "REQ-005-4: Search and type together, inside a region",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      plain(owner, admin, "Barista (weekends)", davao, employment_type: :part_time)
      plain(owner, admin, "Barista (full-time)", davao, employment_type: :full_time)
      plain(owner, admin, "Cashier (weekends)", davao, employment_type: :part_time)
      plain(owner, admin, "Barista (evenings)", cebu, employment_type: :part_time)

      {:ok, view, _html} = live(conn, ~p"/jobs/davao-city")

      search_for(view, "barista")
      assert_patch(view, "/jobs/davao-city?search=barista")

      html = choose_type(view, "part-time", %{search: "barista"})
      assert_patch(view, "/jobs/davao-city?search=barista&type=part-time")

      assert row_titles(html) == ["Barista (weekends)"]
      assert text_of(html, "#jobs-count") == "1 job in Davao City · newest first"
      assert text_of(html, "h1#jobs-heading") == "Jobs in Davao City"
    end

    test "REQ-005-4: Nothing matches", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista (full-time)", davao)

      {:ok, view, _html} = live(conn, ~p"/")
      html = search_for(view, "astronaut")

      assert text_of(html, "#no-jobs") == "No jobs match your search."
      assert row_titles(html) == []
      refute has_element?(view, "#jobs-count")
      assert text_of(html, "#trust-line") == @trust_line

      # And a way to clear the search.
      assert text_of(html, "#clear-search") == "Clear search"
      html = view |> element("#clear-search") |> render_click()

      assert_patch(view, "/")
      assert row_titles(html) == ["Barista (full-time)"]
    end

    test "a searched region with nothing found says so, not that the region is empty",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista (full-time)", davao)

      {:ok, view, html} = live(conn, ~p"/jobs/davao-city?search=astronaut")

      assert text_of(html, "#no-jobs") == "No jobs match your search."
      refute has_element?(view, "#see-all-regions")
      assert has_element?(view, "#clear-search")

      # The same when it is a type that nothing has, and in a region with no jobs at all.
      {:ok, _view, html} = live(conn, ~p"/jobs/davao-city?type=internship")
      assert text_of(html, "#no-jobs") == "No jobs match your search."

      {:ok, _view, html} = live(conn, ~p"/jobs/cebu?search=barista")
      assert text_of(html, "#no-jobs") == "No jobs match your search."
    end

    test "REQ-005-4: Clear the search", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista (weekends)", davao, employment_type: :part_time)
      plain(owner, admin, "Barista (full-time)", davao, employment_type: :full_time)
      plain(owner, admin, "Cashier", davao)

      {:ok, view, html} = live(conn, ~p"/jobs/davao-city?search=barista&type=part-time")
      assert row_titles(html) == ["Barista (weekends)"]

      html = view |> element("#clear-search") |> render_click()

      # The whole list again, in the same region, with the form empty.
      assert_patch(view, "/jobs/davao-city")
      assert length(row_titles(html)) == 3
      assert form_values(html) == {nil, nil}
      refute has_element?(view, "#clear-search")
    end

    test "there is nothing to clear when nothing is searched", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#clear-search")

      # A type alone can be cleared too.
      {:ok, view, _html} = live(conn, ~p"/?type=part-time")
      assert has_element?(view, "#clear-search")
    end

    test "REQ-005-4: A search can be opened again by its address",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      plain(owner, admin, "Barista (weekends)", davao, employment_type: :part_time)
      plain(owner, admin, "Barista (full-time)", davao, employment_type: :full_time)
      plain(owner, admin, "Barista (evenings)", cebu, employment_type: :part_time)

      # As a link opens it: one plain request, no live connection.
      html = conn |> get("/jobs/davao-city?search=barista&type=part-time") |> html_response(200)

      assert row_titles(html) == ["Barista (weekends)"]
      assert form_values(html) == {"barista", "part-time"}
      assert text_of(html, "#jobs-count") == "1 job in Davao City · newest first"

      # The form is an ordinary one that asks for the same address, so it works before
      # the live connection is up.
      form = html |> LazyHTML.from_fragment() |> LazyHTML.query("#search-form")
      assert LazyHTML.attribute(form, "method") == ["get"]
      assert LazyHTML.attribute(form, "action") == ["/jobs/davao-city"]

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#search-words")
             |> LazyHTML.attribute("name") == ["search"]

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#search-type")
             |> LazyHTML.attribute("name") == ["type"]
    end

    test "REQ-005-4: Choosing a region keeps the search",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      plain(owner, admin, "Barista (full-time)", davao)
      plain(owner, admin, "Barista (evenings)", cebu, employment_type: :part_time)
      plain(owner, admin, "Cashier", cebu, employment_type: :part_time)

      {:ok, view, _html} = live(conn, ~p"/?search=barista&type=part-time")
      html = view |> element("#region-choice-cebu") |> render_click()

      assert_patch(view, "/jobs/cebu?search=barista&type=part-time")
      assert row_titles(html) == ["Barista (evenings)"]
      assert form_values(html) == {"barista", "part-time"}

      # And back to every region, still searched.
      view |> element("#region-choice-all") |> render_click()
      assert_patch(view, "/?search=barista&type=part-time")
    end

    test "REQ-005-4: An empty search is no search",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      for title <- ["Barista", "Cashier", "Line cook"], do: plain(owner, admin, title, davao)

      {:ok, view, _html} = live(conn, ~p"/")

      for nothing <- ["", "   "] do
        html = search_for(view, nothing)

        # No words in the address, and the whole list.
        assert_patch(view, "/")
        assert length(row_titles(html)) == 3
        refute has_element?(view, "#clear-search")
      end

      # The same for an address that carries only spaces.
      {:ok, view, html} = live(conn, "/?search=%20%20")
      assert length(row_titles(html)) == 3
      refute has_element?(view, "#clear-search")
    end

    test "the count follows the search", %{conn: conn, owner: owner, admin: admin, davao: davao} do
      for n <- 1..3, do: plain(owner, admin, "Barista number #{n}", davao)
      plain(owner, admin, "Cashier", davao)

      {:ok, _view, html} = live(conn, ~p"/jobs/davao-city?search=barista")

      assert text_of(html, "#jobs-count") == "3 jobs in Davao City · newest first"
    end

    test "typing does not search; only Search, or choosing a type, does",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista", davao)
      plain(owner, admin, "Cashier", davao)

      {:ok, view, _html} = live(conn, ~p"/")

      html =
        view
        |> form("#search-form", %{search: "bar"})
        |> render_change(%{"_target" => ["search"]})

      assert length(row_titles(html)) == 2
      refute_patched(view, "/?search=bar")
    end

    test "words are trimmed and cut at 100 characters, in the address and in the field",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = search_for(view, "  barista  ")
      assert_patch(view, "/?search=barista")
      assert {"barista", _} = form_values(html)

      long = String.duplicate("a", 150)
      html = search_for(view, long)

      assert_patch(view, "/?search=#{String.duplicate("a", 100)}")
      assert {words, _} = form_values(html)
      assert String.length(words) == 100
      assert has_element?(view, ~s(#search-words[maxlength="100"]))
    end

    test "an unknown type, or anything that is not text, is ignored",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      plain(owner, admin, "Barista", davao)

      for address <- [
            "/?type=astronaut",
            "/?type=full_time",
            "/?type[]=part-time",
            "/?search[a]=b",
            "/?type=&search=",
            "/?unknown=1"
          ] do
        {:ok, view, html} = live(conn, address)

        assert row_titles(html) == ["Barista"]
        assert form_values(html) == {nil, nil}
        refute has_element?(view, "#clear-search")
      end

      # A forged type from the form is ignored too.
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_hook(view, "filter", %{"_target" => ["type"], "type" => "astronaut"})
      assert row_titles(html) == ["Barista"]
    end

    test "search works on a hidden region's list too",
         %{conn: conn, owner: owner, admin: admin} do
      baguio = region_fixture(name: "Baguio")
      plain(owner, admin, "Barista", baguio)
      plain(owner, admin, "Cashier", baguio)
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, baguio)

      {:ok, _view, html} = live(conn, ~p"/jobs/baguio?search=cashier")

      assert row_titles(html) == ["Cashier"]
    end

    test "no public screen has an accent button: Search is a primary one", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert text_of(html, "button#search-submit.btn-primary") == "Search"
      refute html =~ "btn-accent"
    end

    test "the search field is named for screen readers", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s(input#search-words[type="search"][aria-label="Search jobs"]))
      assert has_element?(view, ~s(select#search-type[aria-label="Type of work"]))
    end

    test "searched words are filtered out of logged parameters (constitution §4.12)" do
      params = %{"search" => "barista matina", "type" => "part-time", "region" => "davao-city"}

      assert Phoenix.Logger.filter_values(params) == %{
               "search" => "[FILTERED]",
               "type" => "part-time",
               "region" => "davao-city"
             }
    end
  end

  describe "\"Show more\", and what the address keeps (REQ-005-2, plan decision 9)" do
    # `count` Published listings in `region`, "Job number 1" the newest.
    defp jobs(owner, admin, region, count, title \\ "Job number") do
      for n <- 1..count do
        owner
        |> published(admin, "#{title} #{n}", region,
          description: "A steady job with a good team in a busy neighbourhood shop."
        )
        |> approved_ago(n, :minute)
      end
    end

    defp numbered(range, title \\ "Job number"), do: Enum.map(range, &"#{title} #{&1}")

    test "20 rows, then 20 more each time, until there are no more",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      jobs(owner, admin, davao, 45)

      {:ok, view, html} = live(conn, ~p"/")
      assert row_titles(html) == numbered(1..20)

      html = view |> element("#show-more") |> render_click()
      assert_patch(view, "/?shown=40")
      # Added under the rows already there, in order, none twice.
      assert row_titles(html) == numbered(1..40)
      assert has_element?(view, "#show-more")

      html = view |> element("#show-more") |> render_click()
      assert_patch(view, "/?shown=60")
      assert row_titles(html) == numbered(1..45)
      refute has_element?(view, "#show-more")

      # The count never changes: it is of everything listed, not of what is shown.
      assert text_of(html, "#jobs-count") == "45 jobs · newest first"
    end

    test "there is no \"Show more\" when everything is shown",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#show-more")

      jobs(owner, admin, davao, 20)

      {:ok, view, html} = live(conn, ~p"/")
      assert length(row_titles(html)) == 20
      refute has_element?(view, "#show-more")
    end

    test "an address with `shown` delivers that many rows at once, before any live connection",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      jobs(owner, admin, davao, 45)

      html = conn |> get("/?shown=40") |> html_response(200)

      assert row_titles(html) == numbered(1..40)

      # "Show more" is a real link to the next address, and replaces this one in the
      # browser's history, so Back never has to be pressed once per "Show more".
      more = html |> LazyHTML.from_fragment() |> LazyHTML.query("a#show-more")
      assert LazyHTML.attribute(more, "href") == ["/?shown=60"]
      assert LazyHTML.attribute(more, "data-phx-link-state") == ["replace"]

      # Opened live at that address, "Show more" carries on from there.
      {:ok, view, html} = live(conn, "/?shown=40")
      assert row_titles(html) == numbered(1..40)

      html = view |> element("#show-more") |> render_click()
      assert_patch(view, "/?shown=60")
      assert row_titles(html) == numbered(1..45)
    end

    test "`shown` works with a region, a search and a type, and they stay in the address",
         %{conn: conn, owner: owner, admin: admin, davao: davao, cebu: cebu} do
      jobs(owner, admin, davao, 25, "Barista shift")
      jobs(owner, admin, davao, 3, "Cashier shift")
      jobs(owner, admin, cebu, 2, "Barista shift")

      {:ok, view, html} = live(conn, "/jobs/davao-city?search=barista&type=full-time")
      assert length(row_titles(html)) == 20
      assert text_of(html, "#jobs-count") == "25 jobs in Davao City · newest first"

      html = view |> element("#show-more") |> render_click()

      # (The test configuration sorts an address's parameters by name.)
      assert_patch(view, "/jobs/davao-city?search=barista&shown=40&type=full-time")
      assert row_titles(html) == numbered(1..25, "Barista shift")

      # Opened again by that address: the same 25.
      html =
        conn
        |> get("/jobs/davao-city?search=barista&type=full-time&shown=40")
        |> html_response(200)

      assert row_titles(html) == numbered(1..25, "Barista shift")
    end

    test "a new search, a type or a region starts again at 20",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      jobs(owner, admin, davao, 45)

      {:ok, view, _html} = live(conn, "/?shown=40")

      html = view |> element("#region-choice-davao-city") |> render_click()
      assert_patch(view, "/jobs/davao-city")
      assert row_titles(html) == numbered(1..20)

      view |> element("#show-more") |> render_click()
      assert_patch(view, "/jobs/davao-city?shown=40")

      html = view |> form("#search-form", %{search: "job"}) |> render_submit()
      assert_patch(view, "/jobs/davao-city?search=job")
      assert row_titles(html) == numbered(1..20)

      view |> element("#show-more") |> render_click()
      html = view |> element("#clear-search") |> render_click()
      assert_patch(view, "/jobs/davao-city")
      assert row_titles(html) == numbered(1..20)
    end

    test "a `shown` that makes no sense is handled",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      jobs(owner, admin, davao, 45)

      # Nothing, nonsense, too little, and a number between two steps: the first 20.
      for shown <- ["0", "-40", "abc", "", "19", "20", "30", "20.5", "4e1"] do
        html = conn |> get("/?shown=#{shown}") |> html_response(200)
        assert row_titles(html) == numbered(1..20), "shown=#{shown}"
      end

      html = conn |> get("/?shown[]=40") |> html_response(200)
      assert row_titles(html) == numbered(1..20)

      # A step, and a number past one: down to the step.
      html = conn |> get("/?shown=59") |> html_response(200)
      assert row_titles(html) == numbered(1..40)

      # Far too much: no more than the address ever keeps, which here is everything.
      html = conn |> get("/?shown=100000") |> html_response(200)
      assert row_titles(html) == numbered(1..45)
    end

    test "the address keeps up to 200 rows; past that \"Show more\" still works",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      jobs(owner, admin, davao, 225)

      # However much is asked for, 200 rows are delivered at most.
      html = conn |> get("/?shown=100000") |> html_response(200)
      assert length(row_titles(html)) == 200

      {:ok, view, html} = live(conn, "/?shown=200")
      assert row_titles(html) == numbered(1..200)

      # No address to go to now: a button that adds rows where they are.
      assert has_element?(view, "button#show-more")

      html = view |> element("#show-more") |> render_click()
      assert row_titles(html) == numbered(1..220)
      refute_patched(view, "/?shown=220")

      html = view |> element("#show-more") |> render_click()
      assert row_titles(html) == numbered(1..225)
      refute has_element?(view, "#show-more")
    end
  end

  describe "what a search engine reads on a list (REQ-005-9)" do
    # Every test here is one plain request: a search engine reads the first delivery.
    defp first_delivery(conn, path),
      do: conn |> get(path) |> html_response(200) |> LazyHTML.from_fragment()

    defp named(doc, name),
      do: doc |> LazyHTML.query(~s(meta[name="#{name}"])) |> LazyHTML.attribute("content")

    defp canonical(doc),
      do: doc |> LazyHTML.query(~s(link[rel="canonical"])) |> LazyHTML.attribute("href")

    defp site, do: JairojobsWeb.Endpoint.url()

    test "the home page and a region's list each have a title, a one-sentence description and their one address",
         %{conn: conn} do
      doc = first_delivery(conn, "/")

      assert doc |> LazyHTML.query("title") |> LazyHTML.text() ==
               "Jobs in the Philippines, with the salary shown | jairojobs"

      assert named(doc, "description") == [
               "Jobs across the Philippines, newest first, each with its salary shown and checked by jairojobs before it is published."
             ]

      assert canonical(doc) == [site() <> "/"]
      assert named(doc, "robots") == []

      doc = first_delivery(conn, "/jobs/davao-city")

      assert named(doc, "description") == [
               "Jobs in Davao City, newest first, each with its salary shown and checked by jairojobs before it is published."
             ]

      assert canonical(doc) == [site() <> "/jobs/davao-city"]
      assert named(doc, "robots") == []
    end

    test "REQ-005-9: Search results ask not to be listed", %{conn: conn} do
      # Words, a type, or both; in a region or across all.
      for path <- [
            "/jobs/davao-city?search=barista",
            "/jobs/davao-city?type=part-time",
            "/jobs/davao-city?search=barista&type=part-time&shown=40",
            "/?search=barista",
            "/?type=internship"
          ] do
        assert conn |> first_delivery(path) |> named("robots") == ["noindex"], path
      end

      # The same lists, not narrowed, do not ask.
      assert conn |> first_delivery("/jobs/davao-city") |> named("robots") == []
      assert conn |> first_delivery("/") |> named("robots") == []
    end

    test "a narrowed list still states the one address of the list it narrows", %{conn: conn} do
      assert conn
             |> first_delivery("/jobs/davao-city?search=barista&type=part-time&shown=40")
             |> canonical() ==
               [site() <> "/jobs/davao-city"]

      assert conn |> first_delivery("/?search=barista") |> canonical() == [site() <> "/"]
    end

    test "a list opened further is the same page, not another one", %{conn: conn} do
      # `shown` alone narrows nothing: no "do not list", and the plain address is stated,
      # so the same list is not counted twice.
      doc = first_delivery(conn, "/?shown=60")

      assert named(doc, "robots") == []
      assert canonical(doc) == [site() <> "/"]

      # Nor does an empty search, or a type the site does not have.
      assert conn |> first_delivery("/?search=%20&type=astronaut") |> named("robots") == []
    end

    test "REQ-005-9: A hidden region's list asks not to be listed",
         %{conn: conn, owner: owner, admin: admin} do
      baguio = region_fixture(name: "Baguio")
      published(owner, admin, "Barista (full-time)", baguio)

      # While the region is active its list is like any other.
      assert conn |> first_delivery("/jobs/baguio") |> named("robots") == []

      {:ok, hidden} = Jairojobs.Regions.hide_region(admin, baguio)
      assert conn |> first_delivery("/jobs/baguio") |> named("robots") == ["noindex"]

      # The home page, which still lists that region's job, is not affected.
      assert conn |> first_delivery("/") |> named("robots") == []

      # Shown again, it stops asking.
      {:ok, _shown} = Jairojobs.Regions.show_region(admin, hidden)
      assert conn |> first_delivery("/jobs/baguio") |> named("robots") == []
    end

    test "REQ-005-9: A page is complete as first delivered",
         %{conn: conn, owner: owner, admin: admin, davao: davao} do
      published(owner, admin, "Barista (full-time)", davao,
        area: "Matina",
        salary_min: 14_000,
        salary_max: 16_000
      )

      # One request, no script run: the row, with its title and salary, is in it.
      for path <- ["/", "/jobs/davao-city"] do
        html = conn |> get(path) |> html_response(200)

        assert row_titles(html) == ["Barista (full-time)"]
        assert text_of(html, "#job-davao-city--barista-full-time") =~ "₱14,000–16,000/mo"
        assert text_of(html, "#job-davao-city--barista-full-time") =~ "Kape Isla"
        assert text_of(html, "#trust-line") == @trust_line
      end
    end

    test "a list carries no job-posting block and no preview of a listing", %{conn: conn} do
      html = conn |> get("/jobs/davao-city") |> html_response(200)

      refute html =~ "application/ld+json"
      refute html =~ "og:title"
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
end
