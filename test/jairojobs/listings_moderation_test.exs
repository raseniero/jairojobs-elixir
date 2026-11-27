defmodule Jairojobs.ListingsModerationTest do
  @moduledoc """
  Admin moderation of listings (spec 004). Listings reach each status through
  the real context functions, never through a shortcut.
  """
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures
  import Swoosh.TestAssertions

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
    {:ok, listing} = Listings.submit_listing(scope, listing, &admin_url/1)
    listing
  end

  # Everything before this point was setup. Creating accounts and getting a
  # listing into a status send emails of their own (confirmation links, "published");
  # the assertions that follow must only see what the step under test sends.
  defp setup_done, do: flush_emails()

  defp published_listing(scope, admin, attrs \\ %{}) do
    {:ok, listing, _email} =
      Listings.approve_listing(admin, pending_listing(scope, attrs), owner_url(), &public_url/1)

    listing
  end

  # The one email this test's own step sent.
  defp sent_email do
    assert_received {:email, email}
    refute_received {:email, _another}
    email
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
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert listing.status == :published
      assert %DateTime{} = listing.published_at
      assert listing.decided_at == listing.published_at
      assert listing.decided_by_id == admin.user.id
      assert listing.region.id == pending.region_id

      # The owner sees it as Published (REQ-003-13).
      assert [%Listing{status: :published}] = Listings.list_my_listings(employer)
    end

    test "REQ-004-5: approving does not change the listing", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      {:ok, listing, _email} =
        Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

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

      assert {:error, :region_hidden} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert %Listing{status: :pending, published_at: nil, decided_at: nil} = reload(pending)
    end

    test "REQ-004-5: listing is no longer waiting", %{employer: employer, admin: admin} do
      # Withdrawn by its Employer: the status refusal, not "not found".
      withdrawn = pending_listing(employer)
      {:ok, _draft} = Listings.withdraw_listing(employer, withdrawn)

      assert {:error, :not_pending} =
               Listings.approve_listing(admin, withdrawn, owner_url(), &public_url/1)

      assert %Listing{status: :draft, published_at: nil, decided_by_id: nil} = reload(withdrawn)

      # Already approved by another Admin.
      other_admin = admin_scope_fixture()
      approved = pending_listing(employer)

      {:ok, first, _email} =
        Listings.approve_listing(other_admin, approved, owner_url(), &public_url/1)

      assert {:error, :not_pending} =
               Listings.approve_listing(admin, approved, owner_url(), &public_url/1)

      assert reload(approved).decided_by_id == other_admin.user.id
      assert reload(approved).published_at == first.published_at

      # Already rejected by another Admin.
      rejected = pending_listing(employer)

      {:ok, _rejected, _email} =
        Listings.reject_listing(other_admin, rejected, %{reason: @reason}, owner_url())

      assert {:error, :not_pending} =
               Listings.approve_listing(admin, rejected, owner_url(), &public_url/1)

      assert reload(rejected).status == :rejected
    end

    test "REQ-004-5: admin approves their own listing" do
      admin = admin_poster_scope_fixture()
      pending = pending_listing(admin)

      assert {:ok, listing, _email} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert listing.status == :published
      assert listing.decided_by_id == admin.user.id
      assert listing.user_id == admin.user.id
    end

    test "a listing deleted in the meantime is not found", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      {:ok, rejected, _email} =
        Listings.reject_listing(admin, pending, %{reason: @reason}, owner_url())

      {:ok, _deleted} = Listings.delete_listing(employer, rejected)

      assert {:error, :not_found} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

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

      assert {:error, :unauthorized} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

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
      assert {:error, :limit_reached} = Listings.submit_listing(employer, fourth, &admin_url/1)

      {:ok, _rejected, _email} =
        Listings.reject_listing(admin, first, %{reason: @reason}, owner_url())

      assert {:ok, %Listing{status: :pending}} =
               Listings.submit_listing(employer, fourth, &admin_url/1)
    end

    test "a resubmission clears the previous decision", %{employer: employer, admin: admin} do
      {:ok, rejected, _email} =
        Listings.reject_listing(admin, pending_listing(employer), %{reason: @reason}, owner_url())

      assert rejected.decided_at
      assert {:ok, resubmitted} = Listings.submit_listing(employer, rejected, &admin_url/1)

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

    test "REQ-004-7: only a published listing can be taken down",
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
      assert {:error, :not_pending} =
               Listings.approve_listing(admin, taken_down, owner_url(), &public_url/1)

      assert {:error, :not_pending} =
               Listings.reject_listing(admin, taken_down, %{reason: @reason}, owner_url())

      # No Employer action does either.
      assert {:error, :invalid_status} =
               Listings.submit_listing(employer, taken_down, &admin_url/1)

      assert {:error, :invalid_status} = Listings.withdraw_listing(employer, taken_down)
      assert {:error, :invalid_status} = Listings.close_listing(employer, taken_down)
      assert {:error, :locked} = Listings.update_listing(employer, taken_down, %{title: "New"})
      assert {:error, :locked} = Listings.delete_listing(employer, taken_down)

      assert reload(taken_down) == before
    end

    test "REQ-004-7: taking down frees a place", %{employer: employer, admin: admin} do
      [first | _rest] = for _ <- 1..3, do: published_listing(employer, admin)
      fourth = listing_fixture(employer, complete_listing_attrs())
      assert {:error, :limit_reached} = Listings.submit_listing(employer, fourth, &admin_url/1)

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(admin, first, %{reason: @reason}, owner_url())

      assert {:ok, %Listing{status: :pending}} =
               Listings.submit_listing(employer, fourth, &admin_url/1)
    end
  end

  describe "authorization" do
    test "REQ-004-1: only an Admin can decide", %{employer: employer, admin: admin} do
      waiting = pending_listing(employer)
      live = published_listing(employer, admin)

      for scope <- non_admin_scopes(employer) do
        assert {:error, :unauthorized} =
                 Listings.approve_listing(scope, waiting, owner_url(), &public_url/1)

        assert {:error, :unauthorized} =
                 Listings.reject_listing(scope, waiting, %{reason: @reason}, owner_url())

        assert {:error, :unauthorized} =
                 Listings.take_down_listing(scope, live, %{reason: @reason}, owner_url())

        for listing <- [waiting, live] do
          assert {:error, :unauthorized} =
                   Listings.update_listing_as_admin(
                     scope,
                     listing,
                     %{title: "Changed by someone else"},
                     owner_url()
                   )
        end
      end

      assert reload(waiting).title == waiting.title
      assert reload(live).title == live.title

      assert %Listing{status: :pending, decided_at: nil, rejection_reason: nil} = reload(waiting)
      assert %Listing{status: :published, takedown_reason: nil} = reload(live)
      assert reload(live).decided_by_id == admin.user.id
    end

    # spec 005 — REQ-005-6: only an approval gives a listing its public address.
    test "an approval that is refused writes no public address", %{employer: employer} do
      waiting = pending_listing(employer)

      for scope <- non_admin_scopes(employer) do
        assert {:error, :unauthorized} =
                 Listings.approve_listing(scope, waiting, owner_url(), &public_url/1)
      end

      assert reload(waiting).slug == nil
      assert Repo.aggregate(Jairojobs.Listings.ListingAddress, :count) == 0
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

  describe "update_listing_as_admin/4" do
    # What the Admin edit form sends back for a listing nobody has touched.
    defp form_params(%Listing{} = listing) do
      %{
        "title" => listing.title,
        "region_id" => listing.region_id,
        "area" => listing.area,
        "salary_min" => Integer.to_string(listing.salary_min),
        "salary_max" => Integer.to_string(listing.salary_max),
        "employment_type" => Atom.to_string(listing.employment_type),
        "schedule" => listing.schedule,
        "description" => listing.description,
        "requirements" => listing.requirements,
        "benefits" => listing.benefits,
        "business_name" => listing.business_name,
        "business_about" => listing.business_about || ""
      }
    end

    test "REQ-004-8: fix a waiting listing", %{employer: employer, admin: admin} do
      first = pending_listing(employer, title: "Barrista (full-time)")
      second = pending_listing(employer_scope_fixture())

      assert {:ok, %Listing{} = listing, _email} =
               Listings.update_listing_as_admin(
                 admin,
                 first,
                 %{form_params(first) | "title" => "Barista (full-time)"},
                 owner_url()
               )

      assert listing.title == "Barista (full-time)"
      assert listing.status == :pending
      assert listing.submitted_at == first.submitted_at
      assert listing.region.id == first.region_id
      # An edit is not a decision.
      assert {listing.decided_at, listing.decided_by_id, listing.published_at} == {nil, nil, nil}

      # Still at the same place in the queue.
      assert {[one, two], false} = Listings.list_listings_for_moderation(admin, :pending)
      assert [one.id, two.id] == [first.id, second.id]
    end

    test "REQ-004-8: fix a published listing", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      text = "We are a neighbourhood café looking for a barista who enjoys regulars. Fixed."
      other_admin = admin_scope_fixture()

      assert {:ok, listing, _email} =
               Listings.update_listing_as_admin(
                 other_admin,
                 live,
                 %{form_params(live) | "description" => text},
                 owner_url()
               )

      assert listing.description == text
      assert listing.status == :published
      # The record of the approval is untouched.
      assert listing.published_at == live.published_at
      assert listing.decided_at == live.decided_at
      assert listing.decided_by_id == admin.user.id
    end

    test "REQ-004-8: the listing must stay complete", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)
      before = reload(pending)

      broken = [
        {:title, %{"title" => ""}},
        {:title, %{"title" => "Four"}},
        {:region_id, %{"region_id" => ""}},
        {:area, %{"area" => "  "}},
        {:salary_min, %{"salary_min" => "", "salary_max" => ""}},
        {:salary_max, %{"salary_max" => ""}},
        {:salary_max, %{"salary_min" => "16000", "salary_max" => "14000"}},
        {:salary_min, %{"salary_min" => "abc"}},
        {:employment_type, %{"employment_type" => ""}},
        {:description, %{"description" => ""}},
        {:description, %{"description" => String.duplicate("a", 49)}},
        {:business_name, %{"business_name" => ""}},
        {:business_name, %{"business_name" => "K"}},
        {:business_name, %{"business_name" => String.duplicate("a", 81)}},
        {:business_about, %{"business_about" => String.duplicate("a", 501)}}
      ]

      for {field, change} <- broken do
        assert {:error, %Ecto.Changeset{} = changeset} =
                 Listings.update_listing_as_admin(
                   admin,
                   pending,
                   Map.merge(form_params(pending), change),
                   owner_url()
                 )

        assert Map.has_key?(errors_on(changeset), field),
               "expected an error on #{field} for #{inspect(change)}, got: " <>
                 inspect(errors_on(changeset))
      end

      assert reload(pending) == before
    end

    test "REQ-004-8: business name changes on the listing only", %{admin: admin} do
      employer = employer_scope_fixture(business_name: "Kape Isla Cafe")
      live = published_listing(employer, admin)
      assert live.business_name == "Kape Isla Cafe"

      assert {:ok, listing, _email} =
               Listings.update_listing_as_admin(
                 admin,
                 live,
                 %{
                   form_params(live)
                   | "business_name" => "Kape Isla Café",
                     "business_about" => "Family-run since 2019."
                 },
                 owner_url()
               )

      assert listing.business_name == "Kape Isla Café"
      assert listing.business_about == "Family-run since 2019."

      account = Accounts.get_user!(employer.user.id)
      assert account.business_name == "Kape Isla Cafe"
      assert account.business_about == nil
    end

    test "REQ-004-8: other listings cannot be edited", %{employer: employer, admin: admin} do
      needs_changes = listing_in_status_fixture(employer, :rejected)
      closed = listing_in_status_fixture(employer, :closed)
      taken_down = listing_in_status_fixture(employer, :taken_down)

      for listing <- [needs_changes, closed, taken_down] do
        before = reload(listing)

        assert {:error, :not_editable} =
                 Listings.update_listing_as_admin(
                   admin,
                   listing,
                   %{form_params(listing) | "title" => "Changed anyway"},
                   owner_url()
                 )

        assert reload(listing) == before
      end
    end

    test "REQ-004-8: only active regions can be chosen", %{employer: employer, admin: admin} do
      baguio = region_fixture()
      cebu = region_fixture()
      other_hidden = region_fixture(active: false)
      live = published_listing(employer, admin, region_id: baguio.id)
      {:ok, _hidden} = Regions.hide_region(admin, baguio)

      # Keeping the listing's own hidden region is allowed.
      assert {:ok, kept, _email} =
               Listings.update_listing_as_admin(
                 admin,
                 live,
                 %{form_params(live) | "area" => "Session Road"},
                 owner_url()
               )

      assert kept.region_id == baguio.id
      assert kept.area == "Session Road"

      # Another hidden region is not.
      assert {:error, %Ecto.Changeset{} = changeset} =
               Listings.update_listing_as_admin(
                 admin,
                 kept,
                 %{form_params(kept) | "region_id" => other_hidden.id},
                 owner_url()
               )

      assert errors_on(changeset).region_id != []

      # Nor one that does not exist.
      assert {:error, %Ecto.Changeset{}} =
               Listings.update_listing_as_admin(
                 admin,
                 kept,
                 %{form_params(kept) | "region_id" => Ecto.UUID.generate()},
                 owner_url()
               )

      assert reload(live).region_id == baguio.id

      # An active one is.
      assert {:ok, moved, _email} =
               Listings.update_listing_as_admin(
                 admin,
                 kept,
                 %{form_params(kept) | "region_id" => cebu.id},
                 owner_url()
               )

      assert moved.region.id == cebu.id
    end

    test "REQ-004-8: saving without changes does nothing", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      before = reload(live)

      assert {:ok, %Listing{} = listing, :unchanged} =
               Listings.update_listing_as_admin(admin, live, form_params(live), owner_url())

      assert listing.id == live.id
      assert reload(live) == before

      # Stray spaces around a value are not a change either.
      assert {:ok, _listing, :unchanged} =
               Listings.update_listing_as_admin(
                 admin,
                 live,
                 %{form_params(live) | "title" => "  #{live.title}  "},
                 owner_url()
               )

      assert reload(live).updated_at == before.updated_at
    end

    test "REQ-004-8: the listing changed while I was editing",
         %{employer: employer, admin: admin} do
      pending = pending_listing(employer)
      {:ok, _draft} = Listings.withdraw_listing(employer, pending)

      assert {:error, :not_editable} =
               Listings.update_listing_as_admin(
                 admin,
                 pending,
                 %{form_params(pending) | "title" => "Changed after the withdrawal"},
                 owner_url()
               )

      assert %Listing{status: :draft} = stored = reload(pending)
      assert stored.title == pending.title
    end

    test "when two Admins edit the same listing, the later save wins",
         %{employer: employer, admin: admin} do
      # Both open the form on the same version of the listing.
      opened = pending_listing(employer, title: "Barista (full-time)")
      other_admin = admin_scope_fixture()

      {:ok, _first, _email} =
        Listings.update_listing_as_admin(
          admin,
          opened,
          %{form_params(opened) | "title" => "Barista (mornings)", "area" => "Toril"},
          owner_url()
        )

      {:ok, second, _email} =
        Listings.update_listing_as_admin(
          other_admin,
          opened,
          %{form_params(opened) | "title" => "Barista (evenings)"},
          owner_url()
        )

      # The second form still held the old area, so it replaces the first save whole.
      assert second.title == "Barista (evenings)"
      assert second.area == opened.area
    end

    test "status, owner and the times cannot be changed by an Admin edit",
         %{employer: employer, admin: admin} do
      pending = pending_listing(employer)

      forged =
        Map.merge(form_params(pending), %{
          "title" => "Barista (afternoons)",
          "status" => "published",
          "user_id" => admin.user.id,
          "submitted_at" => "2020-01-01T00:00:00Z",
          "published_at" => "2020-01-01T00:00:00Z",
          "decided_by_id" => admin.user.id,
          "rejection_reason" => "forged"
        })

      assert {:ok, listing, _email} =
               Listings.update_listing_as_admin(admin, pending, forged, owner_url())

      assert listing.title == "Barista (afternoons)"
      assert listing.status == :pending
      assert listing.user_id == employer.user.id
      assert listing.submitted_at == pending.submitted_at

      assert {listing.published_at, listing.decided_by_id, listing.rejection_reason} ==
               {nil, nil, nil}
    end

    test "change_listing_as_admin/2 builds the form's changeset",
         %{employer: employer} do
      pending = pending_listing(employer)

      assert %Ecto.Changeset{valid?: true} = Listings.change_listing_as_admin(pending)

      changeset = Listings.change_listing_as_admin(pending, %{"business_name" => ""})
      assert "can't be blank" in errors_on(changeset).business_name
    end
  end

  describe "emails to the listing's owner (REQ-004-9)" do
    test "REQ-004-9: approved email", %{admin: admin} do
      employer = employer_scope_fixture()
      pending = pending_listing(employer, title: "Barista (full-time)")
      setup_done()

      assert {:ok, listing, :sent} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      email = sent_email()
      assert email.to == [{"", employer.user.email}]
      assert email.from == {"jairojobs", "hello@jairojobs.com"}
      assert email.subject == "Your listing is published: Barista (full-time)"
      assert email.text_body =~ "Barista (full-time)"
      assert email.text_body =~ "is published"
      assert email.text_body =~ "https://jairojobs.test/my/listings/#{listing.id}"
      # Since spec 005 it also links to the listing's public page (REQ-005-10).
      assert email.text_body =~
               "https://jairojobs.test/jobs/#{listing.region.slug}/#{listing.slug}"

      assert email.html_body == nil
    end

    # spec 005 — REQ-005-10, which amends REQ-004-9: the approval email gains the link to
    # the public page, placed first, and keeps the link to My listings.
    test "REQ-005-10: The approval email links to the public page", %{admin: admin} do
      employer = employer_scope_fixture()
      # A name no other test has: this file runs alongside others (see the pitfall on
      # fixed region names in `regions_test.exs`). The address is read from the region.
      region = region_fixture(name: "Davao #{System.unique_integer([:positive])}")
      pending = pending_listing(employer, title: "Barista (full-time)", region_id: region.id)
      setup_done()

      assert {:ok, listing, :sent} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      email = sent_email()
      assert email.to == [{"", employer.user.email}]
      assert email.subject == "Your listing is published: Barista (full-time)"

      public = "https://jairojobs.test/jobs/#{region.slug}/barista-full-time"
      mine = "https://jairojobs.test/my/listings/#{listing.id}"

      # It links to the listing's public page, and to the listing in My listings…
      assert email.text_body =~ public
      assert email.text_body =~ mine

      # …each on a line of its own, the public one first.
      lines = String.split(email.text_body, "\n")
      assert Enum.find_index(lines, &(&1 == public)) < Enum.find_index(lines, &(&1 == mine))

      # The public address never carries the listing's id (constitution §4.8).
      refute public =~ listing.id

      # It says what each link is for.
      assert email.text_body =~ "Anyone can see it here. This is the link to share:"
      assert email.text_body =~ "It stays up until you close it."
    end

    test "the other three emails to the owner still carry one link, to My listings",
         %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      waiting = pending_listing(employer)
      setup_done()

      {:ok, _edited, :sent} =
        Listings.update_listing_as_admin(admin, live, %{area: "Lanang"}, owner_url())

      {:ok, _taken_down, :sent} =
        Listings.take_down_listing(admin, live, %{reason: @reason}, owner_url())

      {:ok, _rejected, :sent} =
        Listings.reject_listing(admin, waiting, %{reason: @reason}, owner_url())

      for _ <- 1..3 do
        assert_received {:email, email}
        assert email.text_body =~ "https://jairojobs.test/my/listings/"
        refute email.text_body =~ "/jobs/"
      end
    end

    test "REQ-004-9: rejected email carries the reason", %{employer: employer, admin: admin} do
      pending = pending_listing(employer, title: "Line cook (nights)")
      setup_done()

      assert {:ok, listing, :sent} =
               Listings.reject_listing(admin, pending, %{reason: @reason}, owner_url())

      email = sent_email()
      assert email.to == [{"", employer.user.email}]
      assert email.subject == "Your listing needs changes: Line cook (nights)"
      assert email.text_body =~ @reason
      assert email.text_body =~ "edit it and send it again"
      assert email.text_body =~ "https://jairojobs.test/my/listings/#{listing.id}"
    end

    test "REQ-004-9: taken-down email carries the reason", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin, title: "Cashier (weekends)")
      reason = "The business asked us to remove it."
      setup_done()

      assert {:ok, listing, :sent} =
               Listings.take_down_listing(admin, live, %{reason: reason}, owner_url())

      email = sent_email()
      assert email.to == [{"", employer.user.email}]
      assert email.subject == "Your listing was taken down: Cashier (weekends)"
      assert email.text_body =~ reason
      assert email.text_body =~ "cannot be undone"
      assert email.text_body =~ "https://jairojobs.test/my/listings/#{listing.id}"
    end

    test "REQ-004-9: edit email names what changed", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin, title: "Barrista (full-time)", area: "Matina")
      setup_done()

      assert {:ok, listing, :sent} =
               Listings.update_listing_as_admin(
                 admin,
                 live,
                 %{form_params(live) | "title" => "Barista (full-time)", "area" => "Toril"},
                 owner_url()
               )

      email = sent_email()
      assert email.to == [{"", employer.user.email}]
      assert email.subject == "We edited your listing: Barista (full-time)"
      assert email.text_body =~ "Job title"
      assert email.text_body =~ "Area"
      assert email.text_body =~ "https://jairojobs.test/my/listings/#{listing.id}"

      # It names the parts; it does not quote what they said or say now.
      refute email.text_body =~ "Barrista"
      refute email.text_body =~ "Matina"
      refute email.text_body =~ "Toril"
      refute email.text_body =~ "Salary"
    end

    test "REQ-004-9: the edit email lists each changed part once, by its short name",
         %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      cebu = region_fixture()
      setup_done()

      {:ok, _listing, :sent} =
        Listings.update_listing_as_admin(
          admin,
          live,
          Map.merge(form_params(live), %{
            "region_id" => cebu.id,
            "salary_min" => "15000",
            "salary_max" => "18000",
            "employment_type" => "part_time",
            "schedule" => "Weekends only",
            "description" => String.duplicate("A new description. ", 4),
            "requirements" => "At least 21 years old",
            "benefits" => "Free meals and transport",
            "business_name" => "Kape Isla Café",
            "business_about" => "Family-run since 2019."
          }),
          owner_url()
        )

      body = sent_email().text_body

      for name <- [
            "Region",
            "Salary",
            "Type",
            "Schedule",
            "About the job",
            "Requirements",
            "Benefits",
            "Business name",
            "About the business"
          ] do
        assert body =~ name
      end

      assert length(String.split(body, "Salary")) == 2
      refute body =~ "Job title"
      refute body =~ "15000"
      refute body =~ "15,000"
      refute body =~ "Weekends only"
    end

    test "REQ-004-9: no email for your own action" do
      admin = admin_poster_scope_fixture()
      mine = pending_listing(admin)
      another_of_mine = pending_listing(admin)
      setup_done()

      assert {:ok, pending, :own_listing} =
               Listings.update_listing_as_admin(
                 admin,
                 mine,
                 %{title: "Barista (my own listing)"},
                 owner_url()
               )

      assert {:ok, live, :own_listing} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert {:ok, _taken_down, :own_listing} =
               Listings.take_down_listing(admin, live, %{reason: @reason}, owner_url())

      assert {:ok, _rejected, :own_listing} =
               Listings.reject_listing(admin, another_of_mine, %{reason: @reason}, owner_url())

      refute_email_sent()
    end

    test "an Admin acting on another Admin's listing does email that Admin", %{admin: admin} do
      owner = admin_poster_scope_fixture()
      pending = pending_listing(owner)
      setup_done()

      assert {:ok, _listing, :sent} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert sent_email().to == [{"", owner.user.email}]
    end

    test "an edit that changes nothing sends nothing", %{employer: employer, admin: admin} do
      live = published_listing(employer, admin)
      setup_done()

      assert {:ok, _listing, :unchanged} =
               Listings.update_listing_as_admin(admin, live, form_params(live), owner_url())

      refute_email_sent()
    end

    test "an owner who has since been demoted to Candidate is still emailed", %{admin: admin} do
      owner = admin_poster_scope_fixture()
      pending = pending_listing(owner)
      {:ok, demoted} = Accounts.demote_admin(Scope.system(), owner.user)
      assert demoted.role == :candidate
      setup_done()

      assert {:ok, _listing, :sent} =
               Listings.approve_listing(admin, pending, owner_url(), &public_url/1)

      assert sent_email().to == [{"", owner.user.email}]
    end

    test "a refused action sends nothing", %{employer: employer, admin: admin} do
      pending = pending_listing(employer)
      setup_done()

      assert {:error, %Ecto.Changeset{}} =
               Listings.reject_listing(admin, pending, %{reason: "short"}, owner_url())

      assert {:error, :not_published} =
               Listings.take_down_listing(admin, pending, %{reason: @reason}, owner_url())

      refute_email_sent()
    end
  end

  describe "emails to Admins when a listing is submitted (REQ-004-10)" do
    # Every "waiting" email in the mailbox, by recipient address. Fixtures create
    # Admins of their own (each region is made by one), so these tests name the
    # recipients they care about and never count emails.
    defp waiting_emails(acc \\ %{}) do
      receive do
        {:email, %Swoosh.Email{subject: "A listing is waiting for approval: " <> _} = email} ->
          [{_name, address}] = email.to
          waiting_emails(Map.put(acc, address, email))

        {:email, _other} ->
          waiting_emails(acc)
      after
        0 -> acc
      end
    end

    test "REQ-004-10: submission emails the Admins", %{admin: admin} do
      other_admin = admin_fixture()
      region = region_fixture(name: "Cebu #{System.unique_integer([:positive])}")
      employer = employer_scope_fixture(business_name: "Kape Isla")

      draft =
        listing_fixture(
          employer,
          complete_listing_attrs(title: "Barista (full-time)", region_id: region.id)
        )

      setup_done()

      assert {:ok, pending} = Listings.submit_listing(employer, draft, &admin_url/1)

      emails = waiting_emails()
      assert Map.has_key?(emails, admin.user.email)
      assert Map.has_key?(emails, other_admin.email)
      refute Map.has_key?(emails, employer.user.email)

      email = emails[admin.user.email]
      assert email.from == {"jairojobs", "hello@jairojobs.com"}
      assert email.subject == "A listing is waiting for approval: Barista (full-time)"
      assert email.text_body =~ "Kape Isla"
      assert email.text_body =~ region.name
      assert email.text_body =~ "https://jairojobs.test/admin/listings/#{pending.id}"

      # Nothing else from the listing: not its salary, area or text.
      refute email.text_body =~ "14,000"
      refute email.text_body =~ "14000"
      refute email.text_body =~ "Matina"
      refute email.text_body =~ "neighbourhood café"
      refute email.text_body =~ employer.user.email
    end

    test "REQ-004-10: a resubmission emails the Admins again",
         %{employer: employer, admin: admin} do
      rejected = listing_in_status_fixture(employer, :rejected)
      setup_done()

      assert {:ok, _pending} = Listings.submit_listing(employer, rejected, &admin_url/1)

      assert Map.has_key?(waiting_emails(), admin.user.email)
    end

    test "REQ-004-10: the Admin who submitted is not emailed", %{admin: other_admin} do
      submitter = admin_poster_scope_fixture()
      draft = listing_fixture(submitter, complete_listing_attrs())
      setup_done()

      assert {:ok, _pending} = Listings.submit_listing(submitter, draft, &admin_url/1)

      emails = waiting_emails()
      assert Map.has_key?(emails, other_admin.user.email)
      refute Map.has_key?(emails, submitter.user.email)
    end

    test "REQ-004-10: withdrawing sends nothing", %{employer: employer} do
      pending = pending_listing(employer)
      setup_done()

      assert {:ok, _draft} = Listings.withdraw_listing(employer, pending)

      refute_email_sent()
    end

    test "a submission that is refused sends nothing", %{employer: employer} do
      incomplete = listing_fixture(employer)
      setup_done()

      assert {:error, {:incomplete, _fields}} =
               Listings.submit_listing(employer, incomplete, &admin_url/1)

      refute_email_sent()
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

      {:ok, _resubmitted} = Listings.submit_listing(employer, rejected, &admin_url/1)

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

      # With the time it is accepted. Since spec 005 a listing with a published time
      # also needs its public address, recorded first.
      Repo.insert!(%Jairojobs.Listings.ListingAddress{
        listing_id: pending.id,
        region_id: pending.region_id,
        slug: "a-job"
      })

      raw_update(pending, "status = 'published', published_at = now(), slug = 'a-job'")
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
