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

  describe "access to a listing's Admin view" do
    test "REQ-004-1: employer or candidate is refused", %{conn: conn} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :pending)

      # Its own Employer included: the Admin view is not theirs to open.
      for user <- [employer.user, user_fixture(role: "employer"), user_fixture(role: "candidate")] do
        conn = log_in_user(conn, user)

        assert {:error, {:redirect, %{to: "/", flash: flash}}} =
                 live(conn, ~p"/admin/listings/#{listing.id}")

        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-004-1: visitor is redirected to log in", %{conn: conn} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :pending)

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/listings/#{listing.id}")

      # The link in the email to Admins brings them back here after logging in.
      conn = get(conn, ~p"/admin/listings/#{listing.id}")
      assert get_session(conn, :user_return_to) == "/admin/listings/#{listing.id}"
    end
  end

  describe "the Admin view" do
    setup :log_in_admin

    test "REQ-004-4: review a waiting listing", %{conn: conn} do
      region = region_fixture(name: "Davao #{System.unique_integer([:positive])}")

      employer =
        employer_scope_fixture(
          business_name: "Kape Isla",
          business_about: "Family-run café since 2019."
        )

      listing =
        listing_in_status_fixture(employer, :pending,
          title: "Barista (full-time)",
          region_id: region.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

      # The listing as visitors will see it.
      assert text(view, "#listing-title") == "Barista (full-time)"
      assert text(view, "#listing-business") == "Kape Isla"
      assert text(view, "#listing-salary") == "₱14,000–16,000 / month"
      assert text(view, "#listing-location") == "Matina, #{region.name}"
      assert text(view, "#listing-type") == "Full-time"
      assert text(view, "#listing-schedule") == "Shifting, 6 days"
      detail = text(view, "#listing-detail")
      assert detail =~ "We're a neighbourhood café"
      assert detail =~ "At least 18 years old"
      assert detail =~ "Free meals on shift"
      assert detail =~ "Family-run café since 2019."

      # Who posted it, and when.
      assert text(view, "#listing-status-#{listing.id}") == "Waiting for approval"
      assert text(view, "#listing-poster") =~ "Kape Isla"
      assert text(view, "#listing-poster") =~ employer.user.email
      assert text(view, "#listing-submitted") == "Submitted just now"
      refute has_element?(view, "#your-listing")
      refute has_element?(view, "#listing-decision")
      refute has_element?(view, "#listing-region-hidden")

      assert text(view, "#moderation-help") ==
               "Approving makes it public and emails the employer."

      assert has_element?(view, "#approve-listing")
      assert has_element?(view, "#reject-listing")
      assert has_element?(view, "#admin-edit-listing")
    end

    test "REQ-004-4: actions follow the status", %{conn: conn} do
      all = ~w(approve-listing reject-listing take-down-listing admin-edit-listing)

      offered = %{
        pending: ~w(approve-listing reject-listing admin-edit-listing),
        published: ~w(take-down-listing admin-edit-listing),
        rejected: [],
        closed: [],
        taken_down: []
      }

      for {status, expected} <- offered do
        listing = listing_in_status_fixture(employer_scope_fixture(), status)
        {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

        for action <- all do
          assert has_element?(view, "##{action}") == action in expected,
                 "#{status}: expected #{action} to be #{if action in expected, do: "offered", else: "absent"}"
        end
      end
    end

    test "REQ-004-4: the latest decision is shown", %{conn: conn} do
      employer = employer_scope_fixture()
      pending = listing_in_status_fixture(employer, :pending)
      ana = Scope.for_user(admin_fixture())
      url = &"https://jairojobs.test/my/listings/#{&1.id}"

      {:ok, rejected, _email} =
        Listings.reject_listing(ana, pending, %{reason: "Salary looks like a typo"}, url)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{rejected.id}")

      assert text(view, "#listing-status-#{rejected.id}") == "Needs changes"
      assert text(view, "#listing-decision") == "Rejected just now by #{ana.user.email}"
      assert text(view, "#listing-decision-reason") =~ "Salary looks like a typo"

      # Sent again: no decision until the next one, and the old reason is gone.
      {:ok, _resubmitted} = Listings.submit_listing(employer, rejected)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{rejected.id}")

      refute has_element?(view, "#listing-decision")
      refute has_element?(view, "#listing-decision-reason")
    end

    test "REQ-004-4: the latest decision of an approved or taken-down listing", %{conn: conn} do
      live_listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      closed = listing_in_status_fixture(employer_scope_fixture(), :closed)
      taken_down = listing_in_status_fixture(employer_scope_fixture(), :taken_down)

      for listing <- [live_listing, closed] do
        {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")
        assert text(view, "#listing-decision") =~ ~r/^Approved just now by \S+@\S+$/
        refute has_element?(view, "#listing-decision-reason")
      end

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{taken_down.id}")
      assert text(view, "#listing-decision") =~ ~r/^Taken down just now by \S+@\S+$/
      assert text(view, "#listing-decision-reason") =~ "No longer suitable for the board"
    end

    test "REQ-004-4: a hidden region is flagged", %{conn: conn, admin: admin} do
      baguio = region_fixture(name: "Baguio #{System.unique_integer([:positive])}")

      waiting =
        listing_in_status_fixture(employer_scope_fixture(), :pending, region_id: baguio.id)

      live_listing =
        listing_in_status_fixture(employer_scope_fixture(), :published, region_id: baguio.id)

      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, baguio)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{waiting.id}")

      flag = text(view, "#listing-region-hidden")
      assert flag =~ baguio.name
      assert flag =~ "hidden"
      assert flag =~ "cannot be approved as it is"
      assert flag =~ "Show the region again"
      assert flag =~ "Edit"
      assert flag =~ "reject it with a reason"
      # Approve is still offered.
      assert has_element?(view, "#approve-listing")

      # On a Live listing the pill is there, without the warning about approval.
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{live_listing.id}")

      flag = text(view, "#listing-region-hidden")
      assert flag =~ baguio.name
      assert flag =~ "hidden"
      refute flag =~ "cannot be approved"
    end

    test "REQ-004-4: a Draft is not found", %{conn: conn} do
      employer = employer_scope_fixture()
      draft = listing_fixture(employer, complete_listing_attrs())
      withdrawn = listing_in_status_fixture(employer, :pending)
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      for id <- [draft.id, withdrawn.id, Ecto.UUID.generate(), "not-an-id"] do
        assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/admin/listings/#{id}") end
      end
    end

    test "REQ-004-3: back returns to the same list", %{conn: conn} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)

      {:ok, list, _html} = live(conn, ~p"/admin/listings?status=live")

      {:ok, view, _html} =
        list
        |> element("#admin-listings-#{listing.id} a")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}?from=live")

      {:ok, list, _html} =
        view
        |> element("#back-to-admin-listings")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings?status=live")

      assert has_element?(list, "#filter-live[aria-current=page]")
      assert row_ids(list) == rows([listing])
    end

    test "without a list to go back to, back goes to the queue", %{conn: conn} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)

      for path <- [
            ~p"/admin/listings/#{listing.id}",
            ~p"/admin/listings/#{listing.id}?from=nonsense",
            ~p"/admin/listings/#{listing.id}?from=waiting"
          ] do
        {:ok, view, _html} = live(conn, path)

        assert view
               |> element("#back-to-admin-listings")
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.attribute("href") == ["/admin/listings"]
      end
    end
  end

  describe "approve" do
    setup :log_in_admin

    test "REQ-004-5: approve", %{conn: conn, admin: admin} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}?from=live")

      # Two taps from the queue: open it, approve it. No confirm step.
      assert view
             |> element("#approve-listing")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.attribute("data-confirm") == []

      # Back on the queue, whichever list the Admin came from.
      {:ok, queue, _html} =
        view
        |> element("#approve-listing")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(queue, "#flash-info", "Approved. It is live.")
      assert row_ids(queue) == []

      approved = Listings.get_listing_for_moderation!(admin, listing.id)
      assert approved.status == :published
      assert approved.decided_by_id == admin.user.id
      assert %DateTime{} = approved.published_at

      # Its Employer sees it marked Live in My listings.
      {:ok, mine, _html} =
        build_conn() |> log_in_user(employer.user) |> live(~p"/my/listings")

      assert text(mine, "#listing-status-#{listing.id}") == "Live"
    end

    test "REQ-004-5: hidden region blocks approval", %{conn: conn, admin: admin} do
      region = region_fixture()

      listing =
        listing_in_status_fixture(employer_scope_fixture(), :pending, region_id: region.id)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")
      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, region)

      view |> element("#approve-listing") |> render_click()

      assert has_element?(view, "#flash-error", "Its region is hidden")
      assert has_element?(view, "#flash-error", "Show the region again")
      assert text(view, "#listing-status-#{listing.id}") == "Waiting for approval"
      # The page now shows the listing as it is: with the hidden-region flag.
      assert has_element?(view, "#listing-region-hidden")
      assert Listings.get_listing_for_moderation!(admin, listing.id).status == :pending
    end

    test "REQ-004-5: listing is no longer waiting", %{conn: conn, admin: admin} do
      # Its Employer withdrew it while the Admin had the page open.
      employer = employer_scope_fixture()
      withdrawn = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{withdrawn.id}")
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      # It can no longer be shown to an Admin, so the message is given on the queue.
      {:ok, queue, _html} =
        view
        |> element("#approve-listing")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(
               queue,
               "#flash-error",
               "This listing is no longer waiting for approval."
             )

      assert Listings.get_my_listing!(employer, withdrawn.id).status == :draft

      # Another Admin decided it while this one had the page open.
      rejected = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{rejected.id}")
      reject_listing_fixture(rejected, "Salary looks like a typo")

      view |> element("#approve-listing") |> render_click()

      assert has_element?(
               view,
               "#flash-error",
               "This listing is no longer waiting for approval."
             )

      # The page shows the listing as it now is.
      assert text(view, "#listing-status-#{rejected.id}") == "Needs changes"
      refute has_element?(view, "#approve-listing")
      assert Listings.get_listing_for_moderation!(admin, rejected.id).status == :rejected
    end

    test "REQ-004-5: admin approves their own listing", %{conn: conn, admin: admin} do
      {:ok, _user} =
        Jairojobs.Accounts.update_business_details(admin, %{business_name: "Lutong Bahay"})

      admin = Scope.for_user(Jairojobs.Accounts.get_user!(admin.user.id))
      mine = listing_in_status_fixture(admin, :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{mine.id}")

      assert text(view, "#your-listing") == "Your listing"
      # Nobody is emailed about their own action, and the page does not say otherwise.
      assert text(view, "#moderation-help") == "Approving makes it public."

      {:ok, queue, _html} =
        view
        |> element("#approve-listing")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(queue, "#flash-info", "Approved. It is live.")
      assert Listings.get_listing_for_moderation!(admin, mine.id).status == :published
    end

    test "a listing deleted in the meantime sends the Admin to the queue", %{conn: conn} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

      {:ok, draft} = Listings.withdraw_listing(employer, listing)
      {:ok, _deleted} = Listings.delete_listing(employer, draft)

      {:ok, queue, _html} =
        view
        |> element("#approve-listing")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(queue, "#flash-error", "That listing is not available.")
    end
  end

  describe "reject" do
    setup :log_in_admin

    @reason "Salary looks like a typo — did you mean 14,000?"

    test "REQ-004-6: reject with a reason", %{conn: conn, admin: admin} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

      view |> element("#reject-listing") |> render_click()
      assert_patch(view, ~p"/admin/listings/#{listing.id}/reject")

      # The form replaces the actions; the listing stays in view below it.
      assert has_element?(view, "#decision-form")
      assert has_element?(view, "#decision-form", "The employer will see this.")
      refute has_element?(view, "#approve-listing")
      assert has_element?(view, "#listing-detail")

      {:ok, queue, _html} =
        view
        |> form("#decision-form", decision: %{reason: @reason})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(queue, "#flash-info", "Sent back to the employer.")
      assert row_ids(queue) == []

      rejected = Listings.get_listing_for_moderation!(admin, listing.id)
      assert rejected.status == :rejected
      assert rejected.rejection_reason == @reason
      assert rejected.decided_by_id == admin.user.id

      # Its Employer sees "Needs changes" and the reason.
      {:ok, owner_view, _html} =
        build_conn() |> log_in_user(employer.user) |> live(~p"/my/listings/#{listing.id}")

      assert text(owner_view, "#listing-status-#{listing.id}") == "Needs changes"
      assert text(owner_view, "#listing-rejection-reason") =~ @reason
    end

    test "REQ-004-6: a reason is required", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/reject")

      for reason <- ["", "   ", "Too short", String.duplicate("a", 501)] do
        view |> form("#decision-form", decision: %{reason: reason}) |> render_submit()

        assert has_element?(view, "#decision-form .text-error")
        assert Listings.get_listing_for_moderation!(admin, listing.id).status == :pending
      end

      # The error is also shown while typing.
      html = view |> form("#decision-form", decision: %{reason: "short"}) |> render_change()
      assert html =~ "should be at least 10 character(s)"
    end

    test "REQ-004-6: only a waiting listing can be rejected", %{conn: conn, admin: admin} do
      # A typed or stale address for a listing that is not waiting shows no form.
      live_listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      show = ~p"/admin/listings/#{live_listing.id}"

      assert {:error, {:live_redirect, %{to: ^show, flash: flash}}} =
               live(conn, ~p"/admin/listings/#{live_listing.id}/reject")

      assert flash["error"] == "This listing is no longer waiting for approval."

      # Withdrawn while the form was open: told on the queue, since it is a Draft again.
      employer = employer_scope_fixture()
      withdrawn = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{withdrawn.id}/reject")
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      {:ok, queue, _html} =
        view
        |> form("#decision-form", decision: %{reason: @reason})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(
               queue,
               "#flash-error",
               "This listing is no longer waiting for approval."
             )

      assert Listings.get_my_listing!(employer, withdrawn.id).status == :draft

      # Approved by another Admin while the form was open: back on the Admin view.
      approved = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{approved.id}/reject")
      approve_listing_fixture(approved)

      view |> form("#decision-form", decision: %{reason: @reason}) |> render_submit()
      assert_patch(view, ~p"/admin/listings/#{approved.id}")

      assert has_element?(
               view,
               "#flash-error",
               "This listing is no longer waiting for approval."
             )

      refute has_element?(view, "#decision-form")
      assert Listings.get_listing_for_moderation!(admin, approved.id).status == :published
    end

    test "Cancel returns to the Admin view, and nothing changes", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/reject?from=waiting")

      view |> element("#decision-cancel") |> render_click()
      assert_patch(view, ~p"/admin/listings/#{listing.id}?from=waiting")

      refute has_element?(view, "#decision-form")
      assert has_element?(view, "#approve-listing")
      assert Listings.get_listing_for_moderation!(admin, listing.id).status == :pending
    end
  end

  describe "take down" do
    setup :log_in_admin

    @takedown_reason "The business asked us to remove it."

    test "REQ-004-7: take down with a reason", %{conn: conn, admin: admin} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :published)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}?from=live")

      assert text(view, "#moderation-help") ==
               "Taking it down removes it from public view for good and emails the employer."

      view |> element("#take-down-listing") |> render_click()
      assert_patch(view, ~p"/admin/listings/#{listing.id}/take-down?from=live")

      view |> form("#decision-form", decision: %{reason: @takedown_reason}) |> render_submit()

      # The Admin stays on the listing, which now shows as Taken down.
      assert_patch(view, ~p"/admin/listings/#{listing.id}?from=live")
      assert has_element?(view, "#flash-info", "Taken down.")
      assert text(view, "#listing-status-#{listing.id}") == "Taken down"
      assert text(view, "#listing-decision") == "Taken down just now by #{admin.user.email}"
      assert text(view, "#listing-decision-reason") =~ @takedown_reason
      refute has_element?(view, "#decision-form")

      taken_down = Listings.get_listing_for_moderation!(admin, listing.id)
      assert taken_down.status == :taken_down
      assert taken_down.takedown_reason == @takedown_reason
      assert taken_down.decided_by_id == admin.user.id

      # Its Employer sees "Taken down" and the reason.
      {:ok, owner_view, _html} =
        build_conn() |> log_in_user(employer.user) |> live(~p"/my/listings/#{listing.id}")

      assert text(owner_view, "#listing-status-#{listing.id}") == "Taken down"
      assert text(owner_view, "#listing-takedown-reason") =~ @takedown_reason
    end

    test "REQ-004-7: a reason is required", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/take-down")

      for reason <- ["", "   ", "Too short", String.duplicate("a", 501)] do
        view |> form("#decision-form", decision: %{reason: reason}) |> render_submit()

        assert has_element?(view, "#decision-form .text-error")
        assert Listings.get_listing_for_moderation!(admin, listing.id).status == :published
      end
    end

    test "REQ-004-7: taking down asks first", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

      view |> element("#take-down-listing") |> render_click()

      # Asked for the reason and told it cannot be undone, before anything changes.
      assert has_element?(view, "#decision-form textarea[name='decision[reason]']")
      assert has_element?(view, "#decision-form", "This cannot be undone.")
      assert has_element?(view, "#decision-form", "The employer will see this.")
      assert has_element?(view, "#decision-submit", "Take down")
      assert Listings.get_listing_for_moderation!(admin, listing.id).status == :published
    end

    test "REQ-004-7: only a live listing can be taken down", %{conn: conn, admin: admin} do
      for status <- [:pending, :rejected, :closed, :taken_down] do
        listing = listing_in_status_fixture(employer_scope_fixture(), status)
        show = ~p"/admin/listings/#{listing.id}"

        assert {:error, {:live_redirect, %{to: ^show, flash: flash}}} =
                 live(conn, ~p"/admin/listings/#{listing.id}/take-down")

        assert flash["error"] == "This listing is no longer live."
        assert Listings.get_listing_for_moderation!(admin, listing.id).status == status
      end

      # Closed by its Employer while the form was open.
      employer = employer_scope_fixture()
      closed = listing_in_status_fixture(employer, :published)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{closed.id}/take-down")
      {:ok, _closed} = Listings.close_listing(employer, closed)

      view |> form("#decision-form", decision: %{reason: @takedown_reason}) |> render_submit()
      assert_patch(view, ~p"/admin/listings/#{closed.id}")

      assert has_element?(view, "#flash-error", "This listing is no longer live.")
      assert text(view, "#listing-status-#{closed.id}") == "Closed"
    end

    test "REQ-004-7: taken down is final", %{conn: conn} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :taken_down)

      # Nothing on the Admin view makes it Live again.
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")

      for action <- ~w(approve-listing reject-listing take-down-listing admin-edit-listing) do
        refute has_element?(view, "##{action}")
      end

      refute has_element?(view, "#moderation-box button")
      refute has_element?(view, "#moderation-help")

      # Nor on its Employer's own page.
      {:ok, owner_view, _html} =
        build_conn() |> log_in_user(employer.user) |> live(~p"/my/listings/#{listing.id}")

      for action <- ~w(submit-listing edit-listing withdraw-listing close-listing delete-listing) do
        refute has_element?(owner_view, "##{action}")
      end

      refute has_element?(owner_view, "#listing-status-box button")
    end

    test "Cancel returns to the Admin view, and nothing changes", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/take-down")

      view |> element("#decision-cancel") |> render_click()
      assert_patch(view, ~p"/admin/listings/#{listing.id}")

      assert has_element?(view, "#take-down-listing")
      assert Listings.get_listing_for_moderation!(admin, listing.id).status == :published
    end
  end

  describe "Admin edit" do
    setup :log_in_admin

    test "REQ-004-8: fix a waiting listing", %{conn: conn, admin: admin} do
      first = listing_in_status_fixture(employer_scope_fixture(), :pending, title: "Barrista")
      second = listing_in_status_fixture(employer_scope_fixture(), :pending)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{first.id}?from=waiting")

      {:ok, form_view, _html} =
        view
        |> element("#admin-edit-listing")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings/#{first.id}/edit?from=waiting")

      assert has_element?(
               form_view,
               "#admin-edit-note",
               "The employer will be told what you changed."
             )

      {:ok, view, _html} =
        form_view
        |> form("#listing-form", listing: %{title: "Barista (full-time)"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{first.id}?from=waiting")

      # Back on the listing's Admin view, with a confirmation.
      assert has_element?(view, "#flash-info", "Changes saved.")
      assert text(view, "#listing-title") == "Barista (full-time)"
      assert text(view, "#listing-status-#{first.id}") == "Waiting for approval"

      # Still at the same place in the queue.
      {:ok, queue, _html} = live(conn, ~p"/admin/listings")
      assert row_ids(queue) == rows([first, second])

      assert Listings.get_listing_for_moderation!(admin, first.id).submitted_at ==
               first.submitted_at
    end

    test "REQ-004-8: fix a live listing", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      text = "We are a neighbourhood café looking for a barista who enjoys regulars. Fixed."

      {:ok, form_view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit")

      {:ok, view, _html} =
        form_view
        |> form("#listing-form", listing: %{description: text})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}")

      assert has_element?(view, "#flash-info", "Changes saved.")
      assert text(view, "#listing-detail") =~ "Fixed."
      assert text(view, "#listing-status-#{listing.id}") == "Live"
      assert Listings.get_listing_for_moderation!(admin, listing.id).status == :published
    end

    test "REQ-004-8: the listing must stay complete", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit")

      # Emptying the salary...
      html =
        view
        |> form("#listing-form", listing: %{salary_min: "", salary_max: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      # ...or a maximum below the minimum.
      html =
        view
        |> form("#listing-form", listing: %{salary_min: "16000", salary_max: "14000"})
        |> render_submit()

      assert html =~ "The maximum must be at least the minimum"

      # The business name is required too, and errors show while typing.
      html = view |> form("#listing-form", listing: %{business_name: ""}) |> render_change()
      assert html =~ "can&#39;t be blank"

      stored = Listings.get_listing_for_moderation!(admin, listing.id)
      assert {stored.salary_min, stored.salary_max} == {14_000, 16_000}
      assert stored.business_name == listing.business_name
    end

    test "REQ-004-8: business name changes on the listing only", %{conn: conn, admin: admin} do
      employer = employer_scope_fixture(business_name: "Kape Isla Cafe")
      listing = listing_in_status_fixture(employer, :published)
      {:ok, form_view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit")

      {:ok, view, _html} =
        form_view
        |> form("#listing-form",
          listing: %{business_name: "Kape Isla Café", business_about: "Family-run since 2019."}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}")

      assert text(view, "#listing-business") == "Kape Isla Café"

      assert Listings.get_listing_for_moderation!(admin, listing.id).business_about ==
               "Family-run since 2019."

      account = Jairojobs.Accounts.get_user!(employer.user.id)
      assert account.business_name == "Kape Isla Cafe"
      assert account.business_about == nil
    end

    test "REQ-004-8: other listings cannot be edited", %{conn: conn} do
      for status <- [:rejected, :closed, :taken_down] do
        listing = listing_in_status_fixture(employer_scope_fixture(), status)
        show = ~p"/admin/listings/#{listing.id}"

        # The edit address goes back to the Admin view; no form is shown.
        assert {:error, {:live_redirect, %{to: ^show, flash: flash}}} =
                 live(conn, ~p"/admin/listings/#{listing.id}/edit")

        assert flash["error"] == "This listing can no longer be edited."
      end

      # A Draft has no Admin pages at all.
      draft = listing_fixture(employer_scope_fixture(), complete_listing_attrs())

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/listings/#{draft.id}/edit")
      end
    end

    test "REQ-004-8: only active regions can be chosen", %{conn: conn, admin: admin} do
      baguio = region_fixture(name: "Baguio #{System.unique_integer([:positive])}")
      cebu = region_fixture(name: "Cebu #{System.unique_integer([:positive])}")
      other_hidden = region_fixture(active: false)

      listing =
        listing_in_status_fixture(employer_scope_fixture(), :published, region_id: baguio.id)

      {:ok, _hidden} = Jairojobs.Regions.hide_region(admin, baguio)

      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit")

      options =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#listing-form select[name='listing[region_id]'] option")

      values = LazyHTML.attribute(options, "value")
      labels = Enum.map(options, &strip(LazyHTML.to_html(&1)))

      # I can keep Baguio or choose Cebu, and no other hidden region is offered.
      assert baguio.id in values
      assert cebu.id in values
      refute other_hidden.id in values
      assert "#{baguio.name} (hidden)" in labels

      {:ok, _view, _html} =
        view
        |> form("#listing-form", listing: %{region_id: cebu.id})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}")

      assert Listings.get_listing_for_moderation!(admin, listing.id).region_id == cebu.id
    end

    test "REQ-004-8: saving without changes does nothing", %{conn: conn, admin: admin} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :published)
      before = Listings.get_listing_for_moderation!(admin, listing.id)
      {:ok, form_view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit?from=live")

      {:ok, view, _html} =
        form_view
        |> form("#listing-form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}?from=live")

      assert has_element?(view, "#flash-info", "Nothing was changed.")

      assert Listings.get_listing_for_moderation!(admin, listing.id).updated_at ==
               before.updated_at
    end

    test "REQ-004-8: the listing changed while I was editing", %{conn: conn} do
      # Withdrawn by its Employer: a Draft again, so the message is given on the queue.
      employer = employer_scope_fixture()
      withdrawn = listing_in_status_fixture(employer, :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{withdrawn.id}/edit")
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      {:ok, queue, _html} =
        view
        |> form("#listing-form", listing: %{title: "Changed after the withdrawal"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings")

      assert has_element?(queue, "#flash-error", "This listing can no longer be edited.")
      assert Listings.get_my_listing!(employer, withdrawn.id).title == withdrawn.title

      # Closed by its Employer: back on the Admin view, which shows it as Closed.
      closed = listing_in_status_fixture(employer, :published)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{closed.id}/edit")
      {:ok, _closed} = Listings.close_listing(employer, closed)

      {:ok, show, _html} =
        view
        |> form("#listing-form", listing: %{title: "Changed after it was closed"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/listings/#{closed.id}")

      assert has_element?(show, "#flash-error", "This listing can no longer be edited.")
      assert text(show, "#listing-status-#{closed.id}") == "Closed"
      assert text(show, "#listing-title") == closed.title
    end

    test "Cancel returns to the Admin view", %{conn: conn} do
      listing = listing_in_status_fixture(employer_scope_fixture(), :pending)
      {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit?from=waiting")

      {:ok, show, _html} =
        view
        |> element("#listing-form-cancel")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}?from=waiting")

      assert has_element?(show, "#approve-listing")
    end

    test "REQ-004-1: employer or candidate is refused; visitor is redirected to log in",
         %{conn: _admin_conn} do
      employer = employer_scope_fixture()
      listing = listing_in_status_fixture(employer, :pending)
      path = ~p"/admin/listings/#{listing.id}/edit"

      for user <- [employer.user, user_fixture(role: "candidate")] do
        assert {:error, {:redirect, %{to: "/"}}} =
                 build_conn() |> log_in_user(user) |> live(path)
      end

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), path)
    end
  end

  describe "logging" do
    test "REQ-004: a reason is filtered from logged parameters" do
      params = %{"decision" => %{"reason" => "The business asked us to remove it."}, "id" => "1"}

      assert Phoenix.Logger.filter_values(params) == %{"decision" => "[FILTERED]", "id" => "1"}
    end
  end
end
