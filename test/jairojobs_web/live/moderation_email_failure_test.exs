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
end
