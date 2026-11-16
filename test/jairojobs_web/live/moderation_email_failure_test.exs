defmodule JairojobsWeb.ModerationEmailFailureTest do
  # Not async (constitution §3.5): the mail adapter is application-wide configuration, so
  # swapping in one that fails would break every test running at the same time. These are
  # the screen-level counterparts of `Jairojobs.ListingsEmailFailureTest`: what the Admin
  # and the Employer are told when an email cannot be sent (REQ-004-9, REQ-004-10).
  use JairojobsWeb.ConnCase, async: false

  # The failed sends are logged as warnings; keep them out of the test output.
  @moduletag :capture_log

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings

  # From here on, every email this test sends is refused by the mail service.
  defp mail_fails do
    original = Application.fetch_env!(:jairojobs, Jairojobs.Mailer)
    on_exit(fn -> Application.put_env(:jairojobs, Jairojobs.Mailer, original) end)
    Application.put_env(:jairojobs, Jairojobs.Mailer, adapter: Jairojobs.FailingMailAdapter)
  end

  setup %{conn: conn} do
    admin = admin_fixture()
    %{conn: log_in_user(conn, admin), admin: Scope.for_user(admin)}
  end

  test "REQ-004-9: approving says the employer could not be emailed, and still approves",
       %{conn: conn, admin: admin} do
    listing = listing_in_status_fixture(employer_scope_fixture(), :pending)
    {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}")
    mail_fails()

    {:ok, queue, _html} =
      view
      |> element("#approve-listing")
      |> render_click()
      |> follow_redirect(conn, ~p"/admin/listings")

    assert has_element?(
             queue,
             "#flash-info",
             "Approved. It is live. The employer could not be emailed."
           )

    assert Listings.get_listing_for_moderation!(admin, listing.id).status == :published
  end

  test "REQ-004-9: rejecting and taking down say the employer could not be emailed",
       %{conn: conn, admin: admin} do
    waiting = listing_in_status_fixture(employer_scope_fixture(), :pending)
    live_listing = listing_in_status_fixture(employer_scope_fixture(), :published)
    {:ok, reject, _html} = live(conn, ~p"/admin/listings/#{waiting.id}/reject")
    {:ok, take_down, _html} = live(conn, ~p"/admin/listings/#{live_listing.id}/take-down")
    mail_fails()

    {:ok, queue, _html} =
      reject
      |> form("#decision-form", decision: %{reason: "Salary looks like a typo."})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/listings")

    assert has_element?(
             queue,
             "#flash-info",
             "Sent back to the employer. The employer could not be emailed."
           )

    take_down
    |> form("#decision-form", decision: %{reason: "The business asked us to remove it."})
    |> render_submit()

    assert has_element?(
             take_down,
             "#flash-info",
             "Taken down. The employer could not be emailed."
           )

    assert Listings.get_listing_for_moderation!(admin, waiting.id).status == :rejected
    assert Listings.get_listing_for_moderation!(admin, live_listing.id).status == :taken_down
  end

  test "REQ-004-9: an Admin edit says the employer could not be emailed, and still saves",
       %{conn: conn, admin: admin} do
    listing = listing_in_status_fixture(employer_scope_fixture(), :published)
    {:ok, view, _html} = live(conn, ~p"/admin/listings/#{listing.id}/edit")
    mail_fails()

    {:ok, show, _html} =
      view
      |> form("#listing-form", listing: %{title: "Barista (mornings)"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/listings/#{listing.id}")

    assert has_element?(
             show,
             "#flash-info",
             "Changes saved. The employer could not be emailed."
           )

    assert Listings.get_listing_for_moderation!(admin, listing.id).title == "Barista (mornings)"
  end

  test "REQ-004-10: the Employer sees the usual message when the email to Admins fails" do
    employer = employer_scope_fixture()
    draft = listing_fixture(employer, complete_listing_attrs())

    {:ok, view, _html} =
      build_conn() |> log_in_user(employer.user) |> live(~p"/my/listings/#{draft.id}")

    mail_fails()
    view |> element("#submit-listing") |> render_click()

    assert has_element?(
             view,
             "#flash-info",
             "Submitted. An admin will check it before it goes live."
           )

    refute has_element?(view, "#flash-error")
    assert Listings.get_my_listing!(employer, draft.id).status == :pending
  end
end
