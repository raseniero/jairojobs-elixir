defmodule JairojobsWeb.Employer.PostingJourneyTest do
  @moduledoc """
  One Employer, from "Post a job" to a closed listing, following every
  navigation and redirect the way a user would (spec 003, plan → Test strategy).

  A `Phoenix.LiveViewTest` journey, not a browser test (constitution §3.1):
  JavaScript, CSS and the confirm dialogs are outside it. The two Admin steps
  (reject, publish) are set with the test helper until spec 004 exists.
  """
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp href(html, selector) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute("href")
  end

  test "an employer posts, submits, fixes and closes a listing", %{conn: conn} do
    user = user_fixture(role: "employer")
    region = region_fixture()
    conn = log_in_user(conn, user)

    # 1. "Post a job" in the menu leads to business details first
    home = conn |> get(~p"/") |> html_response(200)
    assert href(home, "#nav-drawer-menu #nav-post-job") == ["/my/listings/new"]

    {:ok, business, _html} =
      conn |> live(~p"/my/listings/new") |> follow_redirect(conn, ~p"/my/business")

    # 2. Saving the business name continues to the listing form
    {:ok, form, _html} =
      business
      |> form("#business-form", business: %{business_name: "Kape Isla"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/my/listings/new")

    # 3. A draft with only a title
    {:ok, show, _html} =
      form
      |> form("#listing-form", listing: %{title: "Barista (full-time)"})
      |> render_submit()
      |> follow_redirect(conn)

    scope = Scope.for_user(Jairojobs.Accounts.get_user!(user.id))
    assert [listing] = Listings.list_my_listings(scope)
    status = "#listing-status-#{listing.id}"

    assert text(show, status) == "Draft"
    assert text(show, "#listing-missing") =~ "Salary"

    # 4. Complete it
    {:ok, form, _html} =
      show
      |> element("#edit-listing")
      |> render_click()
      |> follow_redirect(conn, ~p"/my/listings/#{listing.id}/edit")

    {:ok, show, _html} =
      form
      |> form("#listing-form",
        listing: %{
          region_id: region.id,
          area: "Matina",
          salary_min: "14000",
          salary_max: "16000",
          employment_type: "full_time",
          description: String.duplicate("A friendly neighbourhood café. ", 3)
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/my/listings/#{listing.id}")

    refute has_element?(show, "#listing-missing")
    assert text(show, "#listing-salary") == "₱14,000–16,000 / month"
    assert text(show, "#listing-business") == "Kape Isla"

    # 5. Submit: waiting for approval, one of three places used
    show |> element("#submit-listing") |> render_click()
    assert text(show, status) == "Waiting for approval"

    {:ok, mine, _html} =
      show
      |> element("#back-to-listings")
      |> render_click()
      |> follow_redirect(conn, ~p"/my/listings")

    assert text(mine, "#open-listings-count") == "1 of 3 open listings used"
    assert text(mine, status) == "Waiting for approval"

    # 6. Withdraw, change the title, resubmit
    {:ok, show, _html} =
      mine
      |> element("#my-listings-#{listing.id} a")
      |> render_click()
      |> follow_redirect(conn, ~p"/my/listings/#{listing.id}")

    show |> element("#withdraw-listing") |> render_click()
    assert text(show, status) == "Draft"

    {:ok, form, _html} =
      show
      |> element("#edit-listing")
      |> render_click()
      |> follow_redirect(conn, ~p"/my/listings/#{listing.id}/edit")

    {:ok, show, _html} =
      form
      |> form("#listing-form", listing: %{title: "Barista (full-time, weekends)"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/my/listings/#{listing.id}")

    assert text(show, "#listing-title") == "Barista (full-time, weekends)"
    show |> element("#submit-listing") |> render_click()
    assert text(show, status) == "Waiting for approval"

    # 7a. An Admin rejects it (test helper until spec 004): the reason is shown; resubmit
    scope
    |> Listings.get_my_listing!(listing.id)
    |> set_listing_status(:rejected, reason: "Please name the shift hours")

    {:ok, show, _html} = live(conn, ~p"/my/listings/#{listing.id}")
    assert text(show, status) == "Needs changes"
    assert text(show, "#listing-rejection-reason") =~ "Please name the shift hours"

    show |> element("#submit-listing") |> render_click()
    assert text(show, status) == "Waiting for approval"
    refute has_element?(show, "#listing-rejection-reason")

    # 7b. An Admin publishes it (test helper until spec 004): close it
    scope |> Listings.get_my_listing!(listing.id) |> set_listing_status(:published)

    {:ok, show, _html} = live(conn, ~p"/my/listings/#{listing.id}")
    assert text(show, status) == "Live"

    show |> element("#close-listing") |> render_click()
    assert text(show, status) == "Closed"

    {:ok, mine, _html} =
      show
      |> element("#back-to-listings")
      |> render_click()
      |> follow_redirect(conn, ~p"/my/listings")

    assert text(mine, "#open-listings-count") == "0 of 3 open listings used"
    assert text(mine, status) == "Closed"
  end
end
