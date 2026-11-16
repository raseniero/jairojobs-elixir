defmodule Jairojobs.ListingsModerationTest do
  @moduledoc """
  Admin moderation of listings (spec 004). Listings reach each status through
  the real context functions, never through a shortcut.
  """
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Regions

  @reason "Salary looks like a typo — did you mean 14,000?"

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  defp reload(%Listing{id: id}), do: Repo.get!(Listing, id)

  # A complete listing, submitted by its owner: Waiting for approval.
  defp pending_listing(scope, attrs \\ %{}) do
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    {:ok, listing} = Listings.submit_listing(scope, listing)
    listing
  end

  defp published_listing(scope, admin, attrs \\ %{}) do
    {:ok, listing, _email} =
      Listings.approve_listing(admin, pending_listing(scope, attrs), owner_url())

    listing
  end

  # Everyone who is not an Admin (REQ-004-1), given the listing's owner.
  defp non_admin_scopes(owner) do
    [
      owner,
      employer_scope_fixture(),
      Scope.for_user(user_fixture(role: "candidate")),
      nil,
      Scope.system()
    ]
  end

  setup do
    %{employer: employer_scope_fixture(), admin: admin_scope_fixture()}
  end

  describe "approve_listing/3" do
    test "REQ-004-5: approve", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      assert {:ok, %Listing{} = listing, _email} =
               Listings.approve_listing(admin, pending, owner_url())

      assert listing.status == :published
      assert %DateTime{} = listing.published_at
      assert listing.decided_at == listing.published_at
      assert listing.decided_by_id == admin.user.id
      assert listing.region.id == pending.region_id

      # The owner sees it as Live (REQ-003-13).
      assert [%Listing{status: :published}] = Listings.list_my_listings(employer)
    end

    test "REQ-004-5: approving does not change the listing", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)
      {:ok, listing, _email} = Listings.approve_listing(admin, pending, owner_url())

      content = [
        :title,
        :region_id,
        :area,
        :salary_min,
        :salary_max,
        :employment_type,
        :schedule,
        :description,
        :requirements,
        :benefits,
        :business_name,
        :business_about,
        :submitted_at,
        :user_id
      ]

      assert Map.take(listing, content) == Map.take(pending, content)
    end

    test "REQ-004-5: hidden region blocks approval", %{employer: employer, admin: admin} do
      region = region_fixture()
      pending = pending_listing(employer, region_id: region.id)
      {:ok, _region} = Regions.hide_region(admin, region)

      assert {:error, :region_hidden} = Listings.approve_listing(admin, pending, owner_url())

      assert %Listing{status: :pending, published_at: nil, decided_at: nil} = reload(pending)
    end

    test "REQ-004-5: listing is no longer waiting", %{employer: employer, admin: admin} do
      # Withdrawn by its Employer: the status refusal, not "not found".
      withdrawn = pending_listing(employer)
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)
      assert {:error, :not_pending} = Listings.approve_listing(admin, withdrawn, owner_url())
      assert %Listing{status: :draft, published_at: nil, decided_by_id: nil} = reload(withdrawn)

      # Already approved by another Admin.
      other_admin = admin_scope_fixture()
      approved = pending_listing(employer)
      {:ok, first, _email} = Listings.approve_listing(other_admin, approved, owner_url())
      assert {:error, :not_pending} = Listings.approve_listing(admin, approved, owner_url())
      assert reload(approved).decided_by_id == other_admin.user.id
      assert reload(approved).published_at == first.published_at

      # Already rejected by another Admin.
      rejected = pending_listing(employer)

      {:ok, _rejected, _email} =
        Listings.reject_listing(other_admin, rejected, %{reason: @reason}, owner_url())

      assert {:error, :not_pending} = Listings.approve_listing(admin, rejected, owner_url())
      assert reload(rejected).status == :rejected
    end

    test "REQ-004-5: admin approves their own listing" do
      admin = admin_poster_scope_fixture()
      pending = pending_listing(admin)

      assert {:ok, listing, _email} = Listings.approve_listing(admin, pending, owner_url())
      assert listing.status == :published
      assert listing.decided_by_id == admin.user.id
      assert listing.user_id == admin.user.id
    end

    test "a listing deleted in the meantime is not found", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      {:ok, rejected, _email} =
        Listings.reject_listing(admin, pending, %{reason: @reason}, owner_url())

      {:ok, _deleted} = Listings.delete_listing(employer, rejected)

      assert {:error, :not_found} = Listings.approve_listing(admin, pending, owner_url())

      assert {:error, :not_found} =
               Listings.reject_listing(admin, pending, %{reason: @reason}, owner_url())

      assert {:error, :not_found} =
               Listings.take_down_listing(admin, pending, %{reason: @reason}, owner_url())
    end

    test "an Admin demoted after their scope was built is refused",
         %{employer: employer, admin: admin} do
      # `admin` is not the last Admin: fixtures made others.
      _another = admin_fixture()
      pending = pending_listing(employer)
      {:ok, _demoted} = Accounts.demote_admin(Scope.system(), admin.user)

      # The scope still says Admin; the database no longer does.
      assert Scope.admin?(admin)
      assert {:error, :unauthorized} = Listings.approve_listing(admin, pending, owner_url())
      assert reload(pending).status == :pending
    end
  end

  describe "reject_listing/4" do
    test "REQ-004-6: reject with a reason", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      assert {:ok, %Listing{} = listing, _email} =
               Listings.reject_listing(admin, pending, %{reason: "  #{@reason}  "}, owner_url())

      assert listing.status == :rejected
      assert listing.rejection_reason == @reason
      assert %DateTime{} = listing.decided_at
      assert listing.decided_by_id == admin.user.id
      assert listing.published_at == nil

      # The owner sees it as Needs changes, with the reason (REQ-003-8).
      assert %Listing{status: :rejected, rejection_reason: @reason} =
               Listings.get_my_listing!(employer, listing.id)
    end

    test "REQ-004-6: reject accepts form params with string keys",
         %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      assert {:ok, listing, _email} =
               Listings.reject_listing(admin, pending, %{"reason" => @reason}, owner_url())

      assert listing.rejection_reason == @reason
    end

    test "REQ-004-6: a reason is required", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      for reason <- [nil, "", "          ", "Too short", String.duplicate("a", 501)] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Listings.reject_listing(admin, pending, %{reason: reason}, owner_url())

        assert errors_on(changeset).reason != []
      end

      assert {:error, %Ecto.Changeset{}} =
               Listings.reject_listing(admin, pending, %{}, owner_url())

      assert %Listing{status: :pending, rejection_reason: nil, decided_at: nil} =
               reload(pending)

      # The limits themselves are allowed.
      for reason <- [String.duplicate("a", 10), String.duplicate("a", 500)] do
        listing = pending_listing(employer_scope_fixture())

        assert {:ok, %Listing{rejection_reason: ^reason}, _email} =
                 Listings.reject_listing(admin, listing, %{reason: reason}, owner_url())
      end
    end

    test "REQ-004-6: only a waiting listing can be rejected",
         %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)

      {:ok, needs_changes, _email} =
        Listings.reject_listing(admin, pending_listing(employer), %{reason: @reason}, owner_url())

      {:ok, closed} = Listings.close_listing(employer, published_listing(employer, admin))

      {:ok, taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published_listing(employer_scope_fixture(), admin),
          %{reason: @reason},
          owner_url()
        )

      withdrawn = pending_listing(employer_scope_fixture())
      {:ok, _draft} = Listings.withdraw_listing(Scope.for_user(owner(withdrawn)), withdrawn)

      for listing <- [live, needs_changes, closed, taken_down, withdrawn] do
        before = reload(listing)

        assert {:error, :not_pending} =
                 Listings.reject_listing(admin, listing, %{reason: "Another reason"}, owner_url())

        assert reload(listing) == before
      end
    end

    test "REQ-004-6: rejecting frees a place", %{employer: employer, admin: admin} do
      [first | _rest] = for _ <- 1..3, do: pending_listing(employer)
      fourth = listing_fixture(employer, complete_listing_attrs())
      assert {:error, :limit_reached} = Listings.submit_listing(employer, fourth)

      {:ok, _rejected, _email} =
        Listings.reject_listing(admin, first, %{reason: @reason}, owner_url())

      assert {:ok, %Listing{status: :pending}} = Listings.submit_listing(employer, fourth)
    end

    test "a resubmission clears the previous decision", %{employer: employer, admin: admin} do
      {:ok, rejected, _email} =
        Listings.reject_listing(admin, pending_listing(employer), %{reason: @reason}, owner_url())

      assert rejected.decided_at
      assert {:ok, resubmitted} = Listings.submit_listing(employer, rejected)

      assert %Listing{
               status: :pending,
               rejection_reason: nil,
               decided_at: nil,
               decided_by_id: nil
             } = resubmitted
    end

    test "forged decision fields in the reason params are ignored",
         %{employer: employer, admin: admin} do
      forger = admin_fixture()

      params = %{
        "reason" => @reason,
        "status" => "published",
        "decided_by_id" => forger.id,
        "published_at" => "2020-01-01T00:00:00Z",
        "user_id" => forger.id
      }

      assert {:ok, listing, _email} =
               Listings.reject_listing(admin, pending_listing(employer), params, owner_url())

      assert listing.status == :rejected
      assert listing.decided_by_id == admin.user.id
      assert listing.published_at == nil
      assert listing.user_id == employer.user.id
    end
  end

  describe "take_down_listing/4" do
    test "REQ-004-7: take down with a reason", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      other_admin = admin_scope_fixture()
      reason = "The business asked us to remove it."

      assert {:ok, %Listing{} = listing, _email} =
               Listings.take_down_listing(other_admin, live, %{reason: reason}, owner_url())

      # "No longer visible to the public" is the status until spec 005 (REQ-004-7 rule).
      assert listing.status == :taken_down
      assert listing.takedown_reason == reason
      assert listing.decided_by_id == other_admin.user.id
      assert DateTime.compare(listing.decided_at, live.decided_at) == :gt
      # The approval time is kept: it is the "posted" date.
      assert listing.published_at == live.published_at

      # The owner still has it, marked Taken down, with the reason.
      assert %Listing{status: :taken_down, takedown_reason: ^reason} =
               Listings.get_my_listing!(employer, listing.id)
    end

    test "REQ-004-7: a reason is required", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)

      for reason <- [nil, "", "          ", "Too short", String.duplicate("a", 501)] do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Listings.take_down_listing(admin, live, %{reason: reason}, owner_url())

        assert errors_on(changeset).reason != []
      end

      assert %Listing{status: :published, takedown_reason: nil} = reload(live)
    end

    test "REQ-004-7: only a live listing can be taken down",
         %{employer: employer, admin: admin} do
      waiting = pending_listing(employer)

      {:ok, needs_changes, _email} =
        Listings.reject_listing(admin, pending_listing(employer), %{reason: @reason}, owner_url())

      {:ok, closed} = Listings.close_listing(employer, published_listing(employer, admin))

      {:ok, taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published_listing(employer_scope_fixture(), admin),
          %{reason: @reason},
          owner_url()
        )

      for listing <- [waiting, needs_changes, closed, taken_down] do
        before = reload(listing)

        assert {:error, :not_published} =
                 Listings.take_down_listing(
                   admin,
                   listing,
                   %{reason: "Another reason"},
                   owner_url()
                 )

        assert reload(listing) == before
      end
    end

    test "REQ-004-7: taken down is final", %{employer: employer, admin: admin} do
      {:ok, taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published_listing(employer, admin),
          %{reason: @reason},
          owner_url()
        )

      before = reload(taken_down)

      # No Admin action brings it back.
      assert {:error, :not_pending} = Listings.approve_listing(admin, taken_down, owner_url())

      assert {:error, :not_pending} =
               Listings.reject_listing(admin, taken_down, %{reason: @reason}, owner_url())

      # No Employer action does either.
      assert {:error, :invalid_status} = Listings.submit_listing(employer, taken_down)
      assert {:error, :invalid_status} = Listings.withdraw_listing(employer, taken_down)
      assert {:error, :invalid_status} = Listings.close_listing(employer, taken_down)
      assert {:error, :locked} = Listings.update_listing(employer, taken_down, %{title: "New"})
      assert {:error, :locked} = Listings.delete_listing(employer, taken_down)

      assert reload(taken_down) == before
    end

    test "REQ-004-7: taking down frees a place", %{employer: employer, admin: admin} do
      [first | _rest] = for _ <- 1..3, do: published_listing(employer, admin)
      fourth = listing_fixture(employer, complete_listing_attrs())
      assert {:error, :limit_reached} = Listings.submit_listing(employer, fourth)

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(admin, first, %{reason: @reason}, owner_url())

      assert {:ok, %Listing{status: :pending}} = Listings.submit_listing(employer, fourth)
    end
  end

  describe "authorization" do
    test "REQ-004-1: only an Admin can decide", %{employer: employer, admin: admin} do
      waiting = pending_listing(employer)
      live = published_listing(employer, admin)

      for scope <- non_admin_scopes(employer) do
        assert {:error, :unauthorized} = Listings.approve_listing(scope, waiting, owner_url())

        assert {:error, :unauthorized} =
                 Listings.reject_listing(scope, waiting, %{reason: @reason}, owner_url())

        assert {:error, :unauthorized} =
                 Listings.take_down_listing(scope, live, %{reason: @reason}, owner_url())
      end

      assert %Listing{status: :pending, decided_at: nil, rejection_reason: nil} = reload(waiting)
      assert %Listing{status: :published, takedown_reason: nil} = reload(live)
      assert reload(live).decided_by_id == admin.user.id
    end
  end

  describe "change_reason/1" do
    test "builds a changeset for the reject and take-down forms" do
      assert %Ecto.Changeset{valid?: false} = Listings.change_reason()
      assert %Ecto.Changeset{valid?: true} = Listings.change_reason(%{"reason" => @reason})

      changeset = Listings.change_reason(%{"reason" => "short"})
      assert "should be at least 10 character(s)" in errors_on(changeset).reason
    end
  end

  describe "the approval queue" do
    test "REQ-004-2: longest-waiting first", %{employer: employer, admin: admin} do
      cashier = pending_listing(employer, title: "Cashier (weekends)")
      barista = pending_listing(employer_scope_fixture(), title: "Barista (full-time)")

      assert {[first, second], false} = Listings.list_listings_for_moderation(admin, :pending)
      assert [first.id, second.id] == [cashier.id, barista.id]
      assert first.region.id == cashier.region_id
      assert Listings.count_pending_listings(admin) == 2
    end

    test "REQ-004-2: drafts are not in the queue", %{employer: employer, admin: admin} do
      listing_fixture(employer)
      listing_fixture(employer, complete_listing_attrs())

      assert {[], false} = Listings.list_listings_for_moderation(admin, :pending)
      assert Listings.count_pending_listings(admin) == 0
    end

    test "REQ-004-2: a withdrawn listing leaves the queue", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)
      assert {[_one], false} = Listings.list_listings_for_moderation(admin, :pending)

      {:ok, _draft} = Listings.withdraw_listing(employer, pending)

      assert {[], false} = Listings.list_listings_for_moderation(admin, :pending)
      assert Listings.count_pending_listings(admin) == 0
    end

    test "a listing that was rejected and sent again starts at the back",
         %{employer: employer, admin: admin} do
      first = pending_listing(employer)
      second = pending_listing(employer_scope_fixture())

      {:ok, rejected, _email} =
        Listings.reject_listing(admin, first, %{reason: @reason}, owner_url())

      {:ok, _resubmitted} = Listings.submit_listing(employer, rejected)

      assert {[one, two], false} = Listings.list_listings_for_moderation(admin, :pending)
      assert [one.id, two.id] == [second.id, first.id]
    end

    test "only listings that are waiting are counted", %{employer: employer, admin: admin} do
      pending_listing(employer)
      published_listing(employer, admin)
      listing_in_status_fixture(employer_scope_fixture(), :rejected)
      listing_fixture(employer)

      assert Listings.count_pending_listings(admin) == 1
    end
  end

  describe "list_listings_for_moderation/3" do
    test "REQ-004-3: choose a status", %{employer: employer, admin: admin} do
      waiting = pending_listing(employer)
      older_live = published_listing(employer, admin)
      newer_live = published_listing(employer_scope_fixture(), admin)
      needs_changes = listing_in_status_fixture(employer_scope_fixture(), :rejected)
      taken_down = listing_in_status_fixture(employer_scope_fixture(), :taken_down)
      closed = listing_in_status_fixture(employer_scope_fixture(), :closed)

      ids = fn status ->
        {listings, false} = Listings.list_listings_for_moderation(admin, status)
        Enum.map(listings, & &1.id)
      end

      assert ids.(:pending) == [waiting.id]
      # The most recently changed is first.
      assert ids.(:published) == [newer_live.id, older_live.id]
      assert ids.(:rejected) == [needs_changes.id]
      assert ids.(:taken_down) == [taken_down.id]
      assert ids.(:closed) == [closed.id]
    end

    test "REQ-004-3: a long list is shown in parts", %{admin: admin} do
      # An Admin owner has no limit on open listings.
      owner = admin_poster_scope_fixture()
      region = region_fixture()
      submitted = for _ <- 1..60, do: pending_listing(owner, region_id: region.id)

      assert {first_50, true} = Listings.list_listings_for_moderation(admin, :pending)
      assert length(first_50) == 50

      assert {last_10, false} =
               Listings.list_listings_for_moderation(admin, :pending, offset: 50)

      assert length(last_10) == 10
      assert Enum.map(first_50 ++ last_10, & &1.id) == Enum.map(submitted, & &1.id)

      assert {[_one, _two], true} =
               Listings.list_listings_for_moderation(admin, :pending, limit: 2)
    end

    test "Drafts cannot be asked for", %{employer: employer, admin: admin} do
      listing_fixture(employer, complete_listing_attrs())

      assert {[], false} = Listings.list_listings_for_moderation(admin, :draft)
    end
  end

  describe "get_listing_for_moderation!/2" do
    test "returns a submitted listing with its region, owner and deciding Admin",
         %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      listing = Listings.get_listing_for_moderation!(admin, pending.id)
      assert listing.id == pending.id
      assert listing.region.id == pending.region_id
      assert listing.user.email == employer.user.email
      assert listing.decided_by == nil

      {:ok, _rejected, _email} =
        Listings.reject_listing(admin, pending, %{reason: @reason}, owner_url())

      rejected = Listings.get_listing_for_moderation!(admin, pending.id)
      assert rejected.decided_by.email == admin.user.email
      assert rejected.rejection_reason == @reason
    end

    test "REQ-004-4: a Draft is not found", %{employer: employer, admin: admin} do
      draft = listing_fixture(employer, complete_listing_attrs())
      withdrawn = pending_listing(employer)
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      for id <- [draft.id, withdrawn.id, Ecto.UUID.generate(), "not-an-id"] do
        assert_raise Ecto.NoResultsError, fn ->
          Listings.get_listing_for_moderation!(admin, id)
        end
      end
    end
  end

  describe "reading as someone who is not an Admin" do
    test "REQ-004-1: the queue, the lists and the Admin's read are closed to everyone else",
         %{employer: employer, admin: admin} do
      waiting = pending_listing(employer)
      live = published_listing(employer, admin)

      for scope <- non_admin_scopes(employer) do
        assert Listings.count_pending_listings(scope) == 0
        assert {[], false} = Listings.list_listings_for_moderation(scope, :pending)
        assert {[], false} = Listings.list_listings_for_moderation(scope, :published)

        for listing <- [waiting, live] do
          assert_raise Ecto.NoResultsError, fn ->
            Listings.get_listing_for_moderation!(scope, listing.id)
          end
        end
      end
    end
  end

  describe "database checks (plan decision 12)" do
    # Straight to the table, past every changeset: what the database itself refuses.
    defp raw_update(%Listing{id: id}, set) do
      Repo.query!("UPDATE listings SET #{set} WHERE id = $1", [Ecto.UUID.dump!(id)])
    end

    test "a Published, Closed or Taken down listing must have a published time",
         %{employer: employer} do
      pending = pending_listing(employer)

      for set <- [
            "status = 'published'",
            "status = 'closed'",
            "status = 'taken_down', takedown_reason = 'A reason of some length'"
          ] do
        assert_raise Postgrex.Error, ~r/listings_published_has_time/, fn ->
          raw_update(pending, set)
        end
      end

      raw_update(pending, "status = 'published', published_at = now()")
      assert reload(pending).status == :published
    end

    test "a Rejected listing must have a rejection reason", %{employer: employer} do
      pending = pending_listing(employer)

      assert_raise Postgrex.Error, ~r/listings_rejected_has_reason/, fn ->
        raw_update(pending, "status = 'rejected'")
      end

      raw_update(pending, "status = 'rejected', rejection_reason = 'A reason of some length'")
      assert reload(pending).status == :rejected
    end

    test "a Taken down listing must have a take-down reason",
         %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)

      assert_raise Postgrex.Error, ~r/listings_taken_down_has_reason/, fn ->
        raw_update(live, "status = 'taken_down'")
      end

      raw_update(live, "status = 'taken_down', takedown_reason = 'A reason of some length'")
      assert reload(live).status == :taken_down
    end
  end

  defp owner(%Listing{user_id: id}), do: Accounts.get_user!(id)
end
