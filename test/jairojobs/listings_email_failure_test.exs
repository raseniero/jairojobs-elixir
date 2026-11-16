defmodule Jairojobs.ListingsEmailFailureTest do
  # Not async (constitution §3.5): the mail adapter is application-wide configuration, so
  # swapping in one that fails would break every test running at the same time. ExUnit
  # runs non-async modules on their own, after the async ones.
  use Jairojobs.DataCase, async: false

  import ExUnit.CaptureLog
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures

  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing

  @reason "Salary looks like a typo — did you mean 14,000?"

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  # From here on, every email this test sends fails: refused by the mail service
  # (`{:error, _}`), or with `raise: true`, an exception inside the adapter.
  defp mail_fails(opts \\ []) do
    original = Application.fetch_env!(:jairojobs, Jairojobs.Mailer)
    on_exit(fn -> Application.put_env(:jairojobs, Jairojobs.Mailer, original) end)

    Application.put_env(
      :jairojobs,
      Jairojobs.Mailer,
      [adapter: Jairojobs.FailingMailAdapter] ++ opts
    )
  end

  setup do
    employer = employer_scope_fixture()
    %{employer: employer, admin: admin_scope_fixture()}
  end

  describe "an Admin decision when the email cannot be sent" do
    test "REQ-004-9: the decision stands if the email cannot be sent",
         %{employer: employer, admin: admin} do
      waiting = listing_in_status_fixture(employer, :pending, title: "Barista (full-time)")
      to_reject = listing_in_status_fixture(employer, :pending)
      mail_fails()

      log =
        capture_log(fn ->
          assert {:ok, %Listing{status: :published} = live, :failed} =
                   Listings.approve_listing(admin, waiting, owner_url())

          assert %Listing{status: :published, published_at: %DateTime{}} =
                   Repo.get!(Listing, live.id)

          assert {:ok, %Listing{status: :rejected}, :failed} =
                   Listings.reject_listing(admin, to_reject, %{reason: @reason}, owner_url())

          assert {:ok, %Listing{title: "Barista (mornings)"}, :failed} =
                   Listings.update_listing_as_admin(
                     admin,
                     live,
                     %{title: "Barista (mornings)"},
                     owner_url()
                   )

          assert {:ok, %Listing{status: :taken_down}, :failed} =
                   Listings.take_down_listing(admin, live, %{reason: @reason}, owner_url())
        end)

      assert Repo.get!(Listing, waiting.id).status == :taken_down
      assert Repo.get!(Listing, to_reject.id).rejection_reason == @reason

      # The log says which listing and which email, and nothing about anyone (§4.12).
      assert log =~ waiting.id
      assert log =~ "approved"
      assert log =~ "rejected"
      assert log =~ "edited"
      assert log =~ "taken_down"
      refute log =~ employer.user.email
      refute log =~ "Barista"
      refute log =~ "typo"
    end

    test "REQ-004-9: the decision stands if the mail adapter raises",
         %{employer: employer, admin: admin} do
      waiting = listing_in_status_fixture(employer, :pending)
      mail_fails(raise: true)

      log =
        capture_log(fn ->
          assert {:ok, %Listing{status: :published}, :failed} =
                   Listings.approve_listing(admin, waiting, owner_url())
        end)

      assert Repo.get!(Listing, waiting.id).status == :published
      assert log =~ waiting.id
      refute log =~ employer.user.email
    end
  end
end
