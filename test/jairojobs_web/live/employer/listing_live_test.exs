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

      listing = listing_fixture(employer_scope_fixture())

      for path <- [
            ~p"/my/listings",
            ~p"/my/listings/new",
            ~p"/my/listings/#{listing.id}/edit"
          ] do
        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-003-1: visitor is redirected to log in", %{conn: conn} do
      listing = listing_fixture(employer_scope_fixture())

      for path <- [
            ~p"/my/listings",
            ~p"/my/listings/new",
            ~p"/my/listings/#{listing.id}/edit"
          ] do
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

  describe "post a job" do
    test "REQ-003-2: first post asks for business details", %{conn: conn} do
      user = user_fixture(role: "employer")
      conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/my/business"}}} = live(conn, ~p"/my/listings/new")

      {:ok, business, _html} = live(conn, ~p"/my/business")

      assert {:ok, form, _html} =
               business
               |> form("#business-form", business: %{business_name: "Kape Isla"})
               |> render_submit()
               |> follow_redirect(conn, ~p"/my/listings/new")

      assert has_element?(form, "#listing-form")
    end

    test "REQ-003-2: later posts skip the question", %{conn: conn} do
      %{conn: conn} = log_in_employer(%{conn: conn})
      {:ok, view, _html} = live(conn, ~p"/my/listings")

      assert {:ok, form, _html} =
               view
               |> element("#post-a-job")
               |> render_click()
               |> follow_redirect(conn, ~p"/my/listings/new")

      assert has_element?(form, "#listing-form")
    end

    test "REQ-003-1: admin posts a listing", %{conn: conn} do
      admin = admin_fixture()
      conn = log_in_user(conn, admin)
      {:ok, admin_home, _html} = live(conn, ~p"/admin")

      # no business details yet: the same gate as an Employer
      assert {:error, {:live_redirect, %{to: "/my/business"}}} =
               admin_home
               |> element("#admin-section-post-a-job")
               |> render_click()
               |> follow_redirect(conn, ~p"/my/listings/new")

      {:ok, _user} =
        Jairojobs.Accounts.update_business_details(
          Jairojobs.Accounts.Scope.for_user(admin),
          %{business_name: "jairojobs"}
        )

      {:ok, form, _html} = live(conn, ~p"/my/listings/new")

      form |> form("#listing-form", listing: %{title: "Community manager"}) |> render_submit()

      scope = Jairojobs.Accounts.Scope.for_user(Jairojobs.Accounts.get_user!(admin.id))
      assert [%{title: "Community manager", status: :draft}] = Listings.list_my_listings(scope)
    end

    test "REQ-003-1: the employer menu links to Post a job", %{conn: conn} do
      %{conn: conn} = log_in_employer(%{conn: conn})
      html = conn |> get(~p"/") |> html_response(200)

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#nav-drawer-menu #nav-post-job")
             |> LazyHTML.attribute("href") == ["/my/listings/new"]
    end
  end

  describe "listing form — new" do
    setup :log_in_employer

    test "REQ-003-3: save an unfinished draft", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#listing-form", listing: %{title: "Barista (full-time)"})
               |> render_submit()

      assert [listing] = Listings.list_my_listings(scope)
      assert to == "/my/listings/#{listing.id}"
      assert listing.title == "Barista (full-time)"
      assert listing.status == :draft
      assert Listings.missing_fields(listing) != []
    end

    test "REQ-003-3: a complete draft can be saved in one go", %{conn: conn, scope: scope} do
      region = region_fixture()
      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      view
      |> form("#listing-form",
        listing: %{
          title: "Barista (full-time)",
          region_id: region.id,
          area: "Matina",
          salary_min: "14,000",
          salary_max: "16000",
          employment_type: "full_time",
          schedule: "Shifting, 6 days",
          description: String.duplicate("Friendly café. ", 5),
          requirements: "At least 18 years old",
          benefits: "Free meals on shift"
        }
      )
      |> render_submit()

      assert [listing] = Listings.list_my_listings(scope)
      assert {listing.salary_min, listing.salary_max} == {14_000, 16_000}
      assert listing.region.id == region.id
      assert listing.employment_type == :full_time
      assert listing.status == :draft
      assert Listings.missing_fields(listing) == []
    end

    test "REQ-003-3: title is required", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      assert view |> form("#listing-form", listing: %{title: ""}) |> render_submit() =~
               "can&#39;t be blank"

      assert view |> form("#listing-form", listing: %{title: "Cook"}) |> render_change() =~
               "should be at least 5 character(s)"

      assert has_element?(view, "#listing-form")
      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-3: a filled-in field must still be valid", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      assert view
             |> form("#listing-form",
               listing: %{title: "Barista", salary_min: "abc", salary_max: "16000"}
             )
             |> render_submit() =~ "must be a whole number of pesos"

      assert view
             |> form("#listing-form",
               listing: %{title: "Barista", salary_min: "16000", salary_max: "14000"}
             )
             |> render_submit() =~ "The maximum must be at least the minimum"

      assert view
             |> form("#listing-form",
               listing: %{title: "Barista", salary_min: "14000.50", salary_max: "16000"}
             )
             |> render_submit() =~ "must be a whole number of pesos"

      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-3: only active regions are offered", %{conn: conn} do
      cebu = region_fixture()
      baguio = region_fixture(active: false)

      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      assert has_element?(view, "#listing_region_id option[value='#{cebu.id}']")
      refute has_element?(view, "#listing_region_id option[value='#{baguio.id}']")
    end

    test "REQ-003-3: cancel goes back to My listings", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/my/listings/new")

      assert {:ok, _view, _html} =
               view
               |> element("#listing-form-cancel")
               |> render_click()
               |> follow_redirect(conn, ~p"/my/listings")

      assert Listings.list_my_listings(scope) == []
    end
  end

  describe "listing form — edit" do
    setup :log_in_employer

    test "REQ-003-5: edit a draft", %{conn: conn, scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs(title: "Barista (full-time)"))

      {:ok, view, _html} = live(conn, ~p"/my/listings/#{listing.id}/edit")

      assert view |> element("#listing_title") |> render() =~ "Barista (full-time)"
      assert view |> element("#listing_salary_min") |> render() =~ ~s(value="14000")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#listing-form",
                 listing: %{title: "Senior barista", salary_min: "18000", salary_max: "20000"}
               )
               |> render_submit()

      assert to == "/my/listings/#{listing.id}"

      updated = Listings.get_my_listing!(scope, listing.id)
      assert updated.title == "Senior barista"
      assert {updated.salary_min, updated.salary_max} == {18_000, 20_000}
      assert updated.status == :draft
    end

    test "REQ-003-5: a rejected listing can be edited", %{conn: conn, scope: scope} do
      listing = listing_in_status_fixture(scope, :rejected)
      {:ok, view, _html} = live(conn, ~p"/my/listings/#{listing.id}/edit")

      view |> form("#listing-form", listing: %{area: "Lanang"}) |> render_submit()

      updated = Listings.get_my_listing!(scope, listing.id)
      assert updated.area == "Lanang"
      assert updated.status == :rejected
    end

    test "REQ-003-5: editing a locked listing is refused", %{conn: conn, scope: scope} do
      for status <- [:pending, :published, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)
        show = "/my/listings/#{listing.id}"

        assert {:error, {:live_redirect, %{to: ^show, flash: flash}}} =
                 live(conn, ~p"/my/listings/#{listing.id}/edit")

        assert flash["error"] =~ "can't be edited"
      end
    end

    test "REQ-003-5: a listing locked while the form is open is not changed", %{
      conn: conn,
      scope: scope
    } do
      listing = listing_fixture(scope, complete_listing_attrs())
      {:ok, view, _html} = live(conn, ~p"/my/listings/#{listing.id}/edit")

      {:ok, _pending} = Listings.submit_listing(scope, listing)

      assert {:error, {:live_redirect, %{to: _show}}} =
               view |> form("#listing-form", listing: %{title: "Changed it"}) |> render_submit()

      assert Listings.get_my_listing!(scope, listing.id).title == listing.title
    end

    test "REQ-003-6: editing a draft whose region was hidden keeps the region", %{
      conn: conn,
      scope: scope
    } do
      region = region_fixture()
      listing = listing_fixture(scope, complete_listing_attrs(region_id: region.id))
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin_scope_fixture(), region)

      {:ok, view, _html} = live(conn, ~p"/my/listings/#{listing.id}/edit")

      assert view |> element("#listing_region_id option[value='#{region.id}']") |> render() =~
               "no longer available"

      view |> form("#listing-form", listing: %{title: "Senior barista"}) |> render_submit()

      assert Listings.get_my_listing!(scope, listing.id).region_id == region.id
    end

    test "REQ-003-14: another employer's listing is not found", %{conn: conn} do
      theirs = listing_fixture(employer_scope_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/my/listings/#{theirs.id}/edit")
      end

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/my/listings/#{Ecto.UUID.generate()}/edit")
      end
    end
  end
end
