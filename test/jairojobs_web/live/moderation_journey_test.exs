defmodule JairojobsWeb.ModerationJourneyTest do
  @moduledoc """
  One listing, from an Employer's submission to an Admin's take-down, through
  the real screens of both and following every navigation and redirect the way
  a user would (spec 004, plan → Test strategy). The emails each side receives
  are checked along the way.

  A `Phoenix.LiveViewTest` journey, not a browser test (constitution §3.1):
  JavaScript and CSS are outside it.
  """
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  # The emails sent since the last call, as `{recipient, subject, body}`.
  defp emails(acc \\ []) do
    receive do
      {:email, %Swoosh.Email{to: [{_name, address}]} = email} ->
        emails([{address, email.subject, email.text_body} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp email_to(emails, address) do
    assert [{^address, subject, body}] = Enum.filter(emails, &(elem(&1, 0) == address))
    {subject, body}
  end

  test "a listing is submitted, rejected, fixed, edited, approved and taken down",
       %{conn: conn} do
    region = region_fixture(name: "Davao #{System.unique_integer([:positive])}")
    employer = employer_scope_fixture(business_name: "Kape Isla")
    admin = admin_fixture()
    employer_conn = log_in_user(conn, employer.user)
    admin_conn = log_in_user(build_conn(), admin)
    status = "span[id^=listing-status-]"

    # 1. The Employer posts a complete listing and submits it; the Admin is emailed.
    {:ok, form, _html} = live(employer_conn, ~p"/my/listings/new")

    {:ok, owner_view, _html} =
      form
      |> form("#listing-form",
        listing:
          complete_listing_attrs(title: "Barrista (full-time)", region_id: region.id)
          |> Map.update!(:employment_type, &Atom.to_string/1)
      )
      |> render_submit()
      |> follow_redirect(employer_conn)

    _setup = emails()
    owner_view |> element("#submit-listing") |> render_click()
    assert text(owner_view, status) == "Waiting for approval"

    {subject, body} = emails() |> email_to(admin.email)
    assert subject == "A listing is waiting for approval: Barrista (full-time)"
    assert body =~ "Kape Isla"
    assert body =~ region.name
    [admin_path] = Regex.run(~r{/admin/listings/[0-9a-f-]+}, body)

    # 2. The Admin area says one is waiting; Listings shows it; the row opens it.
    {:ok, home, _html} = live(admin_conn, ~p"/admin")
    assert text(home, "#admin-listings-waiting") == "1 waiting for approval"

    {:ok, queue, _html} =
      home
      |> element("#admin-section-listings")
      |> render_click()
      |> follow_redirect(admin_conn, ~p"/admin/listings")

    assert text(queue, "#filter-waiting") == "Waiting for approval (1)"

    {:ok, review, _html} =
      queue
      |> element("#admin-listings a", "Barrista (full-time)")
      |> render_click()
      |> follow_redirect(admin_conn, admin_path <> "?from=waiting")

    assert text(review, "#listing-poster") =~ employer.user.email
    assert text(review, "#listing-salary") == "₱14,000–16,000 / month"

    # 3. Rejected with a reason: back on the queue, now empty; the Employer is emailed.
    review |> element("#reject-listing") |> render_click()

    {:ok, queue, _html} =
      review
      |> form("#decision-form", decision: %{reason: "Please name the shift hours."})
      |> render_submit()
      |> follow_redirect(admin_conn, ~p"/admin/listings")

    assert text(queue, "#no-admin-listings") == "Nothing is waiting for approval."

    {subject, body} = emails() |> email_to(employer.user.email)
    assert subject == "Your listing needs changes: Barrista (full-time)"
    assert body =~ "Please name the shift hours."
    [owner_path] = Regex.run(~r{/my/listings/[0-9a-f-]+}, body)

    # 4. The Employer follows the link, sees the reason, edits, resubmits.
    {:ok, owner_view, _html} = live(employer_conn, owner_path)
    assert text(owner_view, status) == "Needs changes"
    assert text(owner_view, "#listing-rejection-reason") =~ "Please name the shift hours."

    {:ok, form, _html} =
      owner_view
      |> element("#edit-listing")
      |> render_click()
      |> follow_redirect(employer_conn, owner_path <> "/edit")

    {:ok, owner_view, _html} =
      form
      |> form("#listing-form", listing: %{schedule: "Mornings, 6 days"})
      |> render_submit()
      |> follow_redirect(employer_conn, owner_path)

    owner_view |> element("#submit-listing") |> render_click()
    assert text(owner_view, status) == "Waiting for approval"

    {subject, _body} = emails() |> email_to(admin.email)
    assert subject == "A listing is waiting for approval: Barrista (full-time)"

    # 5. The Admin fixes a typo with Edit; the Employer is told which part changed.
    {:ok, review, _html} = live(admin_conn, admin_path)
    assert text(review, "#listing-schedule") == "Mornings, 6 days"
    refute has_element?(review, "#listing-decision")

    {:ok, edit, _html} =
      review
      |> element("#admin-edit-listing")
      |> render_click()
      |> follow_redirect(admin_conn, admin_path <> "/edit")

    {:ok, review, _html} =
      edit
      |> form("#listing-form", listing: %{title: "Barista (full-time)"})
      |> render_submit()
      |> follow_redirect(admin_conn, admin_path)

    assert text(review, "#listing-title") == "Barista (full-time)"
    assert text(review, status) == "Waiting for approval"

    {subject, body} = emails() |> email_to(employer.user.email)
    assert subject == "We edited your listing: Barista (full-time)"
    assert body =~ "Job title"
    refute body =~ "Barrista"

    # 6. Approved: the Employer is emailed, and My listings shows it Live.
    {:ok, _queue, _html} =
      review
      |> element("#approve-listing")
      |> render_click()
      |> follow_redirect(admin_conn, ~p"/admin/listings")

    {subject, _body} = emails() |> email_to(employer.user.email)
    assert subject == "Your listing is live: Barista (full-time)"

    {:ok, mine, _html} = live(employer_conn, ~p"/my/listings")
    assert text(mine, status) == "Live"
    assert text(mine, "#open-listings-count") == "1 of 3 open listings used"

    # 7. Later the Admin finds it under Live and takes it down with a reason.
    {:ok, live_list, _html} = live(admin_conn, ~p"/admin/listings?status=live")

    {:ok, review, _html} =
      live_list
      |> element("#admin-listings a", "Barista (full-time)")
      |> render_click()
      |> follow_redirect(admin_conn, admin_path <> "?from=live")

    review |> element("#take-down-listing") |> render_click()

    review
    |> form("#decision-form", decision: %{reason: "The business asked us to remove it."})
    |> render_submit()

    assert_patch(review, admin_path <> "?from=live")
    assert text(review, status) == "Taken down"
    assert text(review, "#listing-decision") == "Taken down just now by #{admin.email}"

    {subject, body} = emails() |> email_to(employer.user.email)
    assert subject == "Your listing was taken down: Barista (full-time)"
    assert body =~ "The business asked us to remove it."

    # The Employer sees it Taken down, with the reason, and has their place back.
    {:ok, owner_view, _html} = live(employer_conn, owner_path)
    assert text(owner_view, status) == "Taken down"
    assert text(owner_view, "#listing-takedown-reason") =~ "The business asked us to remove it."
    refute has_element?(owner_view, "#listing-status-box button")

    {:ok, mine, _html} = live(employer_conn, ~p"/my/listings")
    assert text(mine, "#open-listings-count") == "0 of 3 open listings used"
  end
end
