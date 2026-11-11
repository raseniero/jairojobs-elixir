defmodule Jairojobs.ListingsTest do
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing

  # Scopes that may never post or touch listings (REQ-003-1).
  defp non_poster_scopes do
    [Scope.for_user(user_fixture(role: "candidate")), nil, Scope.system()]
  end

  # The raw centavo columns, to prove what is stored (constitution §4.5).
  defp stored_salary(listing) do
    Repo.one!(
      from l in "listings",
        where: l.id == type(^listing.id, Ecto.UUID),
        select: {l.salary_min_centavos, l.salary_max_centavos}
    )
  end

  setup do
    %{scope: employer_scope_fixture()}
  end

  describe "create_listing/2" do
    test "REQ-003-3: save an unfinished draft", %{scope: scope} do
      assert {:ok, %Listing{} = listing} =
               Listings.create_listing(scope, %{title: "Barista (full-time)"})

      assert listing.status == :draft
      assert listing.title == "Barista (full-time)"
      assert listing.user_id == scope.user.id
      assert listing.region == nil
      assert listing.salary_min == nil
      assert listing.business_name == nil
      assert listing.submitted_at == nil
    end

    test "REQ-003-3: a complete draft is saved with its salary in centavos", %{scope: scope} do
      region = region_fixture()

      assert {:ok, listing} =
               Listings.create_listing(scope, complete_listing_attrs(region_id: region.id))

      assert listing.status == :draft
      assert listing.region.id == region.id
      assert {listing.salary_min, listing.salary_max} == {14_000, 16_000}
      assert stored_salary(listing) == {1_400_000, 1_600_000}
      assert listing.employment_type == :full_time
    end

    test "REQ-003-3: title is required", %{scope: scope} do
      for title <- [nil, "", "   "] do
        assert {:error, changeset} = Listings.create_listing(scope, %{title: title})
        assert "can't be blank" in errors_on(changeset).title
      end

      assert {:error, changeset} = Listings.create_listing(scope, %{title: "Cook"})
      assert "should be at least 5 character(s)" in errors_on(changeset).title

      assert {:error, changeset} =
               Listings.create_listing(scope, %{title: String.duplicate("a", 101)})

      assert "should be at most 100 character(s)" in errors_on(changeset).title

      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-3: a filled-in field must still be valid", %{scope: scope} do
      invalid = fn attrs ->
        assert {:error, changeset} =
                 Listings.create_listing(scope, Map.put(attrs, :title, "Barista"))

        errors_on(changeset)
      end

      assert "must be a whole number of pesos" in invalid.(%{
               salary_min: "abc",
               salary_max: 16_000
             }).salary_min

      assert "must be a whole number of pesos" in invalid.(%{
               salary_min: "14000.50",
               salary_max: 16_000
             }).salary_min

      assert "The maximum must be at least the minimum" in invalid.(%{
               salary_min: 16_000,
               salary_max: 14_000
             }).salary_max

      assert "must be at least ₱1,000" in invalid.(%{salary_min: 999, salary_max: 16_000}).salary_min

      assert "must be at most ₱1,000,000" in invalid.(%{
               salary_min: 14_000,
               salary_max: 1_000_001
             }).salary_max

      assert "Enter the maximum as well" in invalid.(%{salary_min: 14_000}).salary_max
      assert "Enter the minimum as well" in invalid.(%{salary_max: 16_000}).salary_min

      assert "is invalid" in invalid.(%{employment_type: "freelance"}).employment_type
      assert invalid.(%{area: String.duplicate("a", 81)}).area != []
      assert invalid.(%{schedule: String.duplicate("a", 81)}).schedule != []
      assert invalid.(%{description: String.duplicate("a", 5_001)}).description != []
      assert invalid.(%{requirements: String.duplicate("a", 3_001)}).requirements != []
      assert invalid.(%{benefits: String.duplicate("a", 3_001)}).benefits != []
      assert invalid.(%{region_id: Ecto.UUID.generate()}).region_id != []

      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-4: salary range must make sense", %{scope: scope} do
      assert {:error, changeset} =
               Listings.create_listing(scope, %{
                 title: "Barista",
                 salary_min: 16_000,
                 salary_max: 14_000
               })

      assert errors_on(changeset).salary_max == ["The maximum must be at least the minimum"]
    end

    test "REQ-003-4: same minimum and maximum is allowed", %{scope: scope} do
      assert {:ok, listing} =
               Listings.create_listing(scope, %{
                 title: "Barista",
                 salary_min: "15,000",
                 salary_max: "₱15,000"
               })

      assert {listing.salary_min, listing.salary_max} == {15_000, 15_000}
    end

    test "REQ-003-3: a short description can be saved in a draft", %{scope: scope} do
      assert {:ok, listing} =
               Listings.create_listing(scope, %{title: "Barista", description: "  Soon.  "})

      assert listing.description == "Soon."
    end

    test "REQ-003-2: first post asks for business details" do
      scope = Scope.for_user(user_fixture(role: "employer"))

      assert {:error, :business_details_required} =
               Listings.create_listing(scope, %{title: "Barista"})

      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-1: admin posts a listing" do
      scope = admin_poster_scope_fixture()

      assert {:ok, listing} = Listings.create_listing(scope, %{title: "Barista"})
      assert listing.status == :draft
      assert listing.user_id == scope.user.id
    end

    test "REQ-003-1: candidate is refused" do
      for scope <- non_poster_scopes() do
        assert {:error, :unauthorized} = Listings.create_listing(scope, %{title: "Barista"})
      end
    end

    test "REQ-003-3: status, owner and business details cannot be set from params", %{
      scope: scope
    } do
      other = employer_scope_fixture()

      assert {:ok, listing} =
               Listings.create_listing(scope, %{
                 title: "Barista",
                 status: "published",
                 user_id: other.user.id,
                 business_name: "Forged",
                 rejection_reason: "Forged",
                 submitted_at: DateTime.utc_now()
               })

      assert listing.status == :draft
      assert listing.user_id == scope.user.id
      assert listing.business_name == nil
      assert listing.rejection_reason == nil
      assert listing.submitted_at == nil
    end
  end

  describe "list_my_listings/1" do
    test "REQ-003-13: see my listings, most recently changed first", %{scope: scope} do
      first = listing_fixture(scope)
      second = listing_fixture(scope, complete_listing_attrs())

      assert [newest, oldest] = Listings.list_my_listings(scope)
      assert {newest.id, oldest.id} == {second.id, first.id}
      assert newest.region.id == second.region_id
      assert oldest.region == nil
    end

    test "REQ-003-14: my listings shows only mine", %{scope: scope} do
      mine = listing_fixture(scope)
      listing_fixture(employer_scope_fixture())

      assert Enum.map(Listings.list_my_listings(scope), & &1.id) == [mine.id]
    end

    test "REQ-003-1: nothing is listed for a scope that may not post" do
      for scope <- non_poster_scopes() do
        assert Listings.list_my_listings(scope) == []
      end
    end
  end

  describe "get_my_listing!/2" do
    test "REQ-003-10: returns my listing with its region", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())

      assert fetched = Listings.get_my_listing!(scope, listing.id)
      assert fetched.id == listing.id
      assert fetched.region.id == listing.region_id
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_fixture(employer_scope_fixture())

      assert_raise Ecto.NoResultsError, fn -> Listings.get_my_listing!(scope, theirs.id) end
    end

    test "REQ-003-14: an admin cannot open someone else's listing here", %{scope: scope} do
      listing = listing_fixture(scope)

      assert_raise Ecto.NoResultsError, fn ->
        Listings.get_my_listing!(admin_poster_scope_fixture(), listing.id)
      end
    end

    test "REQ-003-14: unknown and malformed ids are not found either", %{scope: scope} do
      assert_raise Ecto.NoResultsError, fn ->
        Listings.get_my_listing!(scope, Ecto.UUID.generate())
      end

      assert_raise Ecto.NoResultsError, fn -> Listings.get_my_listing!(scope, "not-a-uuid") end

      listing = listing_fixture(scope)

      for other <- non_poster_scopes() do
        assert_raise Ecto.NoResultsError, fn -> Listings.get_my_listing!(other, listing.id) end
      end
    end
  end

  describe "update_listing/3" do
    test "REQ-003-5: edit a draft", %{scope: scope} do
      listing = listing_fixture(scope)

      assert {:ok, updated} =
               Listings.update_listing(scope, listing, %{
                 title: "Senior barista",
                 salary_min: 18_000,
                 salary_max: 20_000
               })

      assert updated.title == "Senior barista"
      assert {updated.salary_min, updated.salary_max} == {18_000, 20_000}
      assert updated.status == :draft
    end

    test "REQ-003-5: a rejected listing can be edited and stays rejected", %{scope: scope} do
      listing = listing_in_status_fixture(scope, :rejected)

      assert {:ok, updated} = Listings.update_listing(scope, listing, %{title: "Senior barista"})
      assert updated.title == "Senior barista"
      assert updated.status == :rejected
      assert updated.rejection_reason == listing.rejection_reason
    end

    test "REQ-003-5: a filled-in field can be cleared again in a draft", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())

      assert {:ok, updated} =
               Listings.update_listing(scope, listing, %{
                 salary_min: "",
                 salary_max: "",
                 area: "",
                 region_id: ""
               })

      assert {updated.salary_min, updated.salary_max, updated.area, updated.region} ==
               {nil, nil, nil, nil}
    end

    test "REQ-003-5: the same field rules apply as for a new draft", %{scope: scope} do
      listing = listing_fixture(scope)

      assert {:error, changeset} = Listings.update_listing(scope, listing, %{title: ""})
      assert "can't be blank" in errors_on(changeset).title

      assert {:error, changeset} =
               Listings.update_listing(scope, listing, %{salary_min: 16_000, salary_max: 14_000})

      assert "The maximum must be at least the minimum" in errors_on(changeset).salary_max
    end

    test "REQ-003-5: editing a locked listing is refused", %{scope: scope} do
      for status <- [:pending, :published, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)

        assert {:error, :locked} = Listings.update_listing(scope, listing, %{title: "Changed it"})
        assert Listings.get_my_listing!(scope, listing.id).title == listing.title
      end
    end

    test "REQ-003-5: a stale copy cannot be used to edit a locked listing", %{scope: scope} do
      draft = listing_fixture(scope, complete_listing_attrs())
      set_listing_status(draft, :pending)

      assert {:error, :locked} = Listings.update_listing(scope, draft, %{title: "Changed it"})
    end

    test "REQ-003-5: status and owner cannot be changed by an edit", %{scope: scope} do
      listing = listing_fixture(scope)

      assert {:ok, updated} =
               Listings.update_listing(scope, listing, %{
                 title: "Senior barista",
                 status: "published",
                 user_id: employer_scope_fixture().user.id
               })

      assert updated.status == :draft
      assert updated.user_id == scope.user.id
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_fixture(employer_scope_fixture())

      assert {:error, :not_found} = Listings.update_listing(scope, theirs, %{title: "Hijacked"})

      assert {:error, :not_found} =
               Listings.update_listing(admin_poster_scope_fixture(), theirs, %{title: "Hijacked"})

      for other <- non_poster_scopes() do
        assert {:error, :unauthorized} =
                 Listings.update_listing(other, theirs, %{title: "Hijacked"})
      end

      assert Repo.get!(Listing, theirs.id).title == theirs.title
    end
  end

  describe "delete_listing/2" do
    test "REQ-003-11: delete a draft", %{scope: scope} do
      listing = listing_fixture(scope)

      assert {:ok, %Listing{}} = Listings.delete_listing(scope, listing)
      assert Listings.list_my_listings(scope) == []
      assert_raise Ecto.NoResultsError, fn -> Listings.get_my_listing!(scope, listing.id) end
    end

    test "REQ-003-11: delete a rejected listing", %{scope: scope} do
      listing = listing_in_status_fixture(scope, :rejected)

      assert {:ok, %Listing{}} = Listings.delete_listing(scope, listing)
      assert Listings.list_my_listings(scope) == []
    end

    test "REQ-003-11: other listings cannot be deleted", %{scope: scope} do
      for status <- [:pending, :published, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)

        assert {:error, :locked} = Listings.delete_listing(scope, listing)
        assert Listings.get_my_listing!(scope, listing.id).status == status
      end
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_fixture(employer_scope_fixture())

      assert {:error, :not_found} = Listings.delete_listing(scope, theirs)
      assert {:error, :not_found} = Listings.delete_listing(admin_poster_scope_fixture(), theirs)

      for other <- non_poster_scopes() do
        assert {:error, :unauthorized} = Listings.delete_listing(other, theirs)
      end

      assert Repo.get!(Listing, theirs.id)
    end
  end

  describe "missing_fields/1" do
    test "REQ-003-4: complete listing", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())
      assert Listings.missing_fields(listing) == []
    end

    test "REQ-003-4: optional fields are not needed", %{scope: scope} do
      listing =
        listing_fixture(
          scope,
          complete_listing_attrs(schedule: nil, requirements: nil, benefits: nil)
        )

      assert Listings.missing_fields(listing) == []
    end

    test "REQ-003-4: salary range is required", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs(salary_min: nil, salary_max: nil))
      assert Listings.missing_fields(listing) == [:salary]
    end

    test "REQ-003-4: a title-only draft is missing everything else, in form order", %{
      scope: scope
    } do
      assert Listings.missing_fields(listing_fixture(scope)) ==
               [:region, :area, :salary, :employment_type, :description]
    end

    test "REQ-003-4: about the job needs at least 50 characters", %{scope: scope} do
      short = listing_fixture(scope, complete_listing_attrs(description: "Too short."))
      assert Listings.missing_fields(short) == [:description]

      exact =
        listing_fixture(scope, complete_listing_attrs(description: String.duplicate("a", 50)))

      assert Listings.missing_fields(exact) == []
    end
  end

  describe "submit_listing/2" do
    test "REQ-003-6: submit a complete draft", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())

      assert {:ok, submitted} = Listings.submit_listing(scope, listing)
      assert submitted.status == :pending
      assert %DateTime{} = submitted.submitted_at
      assert submitted.business_name == scope.user.business_name
      assert submitted.region.id == listing.region_id
      assert Listings.count_open_listings(scope) == 1
    end

    test "REQ-003-6: incomplete draft cannot be submitted", %{scope: scope} do
      listing =
        listing_fixture(
          scope,
          complete_listing_attrs(salary_min: nil, salary_max: nil, description: nil)
        )

      assert {:error, {:incomplete, [:salary, :description]}} =
               Listings.submit_listing(scope, listing)

      assert Listings.get_my_listing!(scope, listing.id).status == :draft
      assert Listings.count_open_listings(scope) == 0
    end

    test "REQ-003-6: region was hidden in the meantime", %{scope: scope} do
      region = region_fixture(name: "Baguio #{System.unique_integer([:positive])}")
      listing = listing_fixture(scope, complete_listing_attrs(region_id: region.id))
      {:ok, _region} = Jairojobs.Regions.hide_region(admin_scope_fixture(), region)

      assert {:error, :region_hidden} = Listings.submit_listing(scope, listing)
      assert Listings.get_my_listing!(scope, listing.id).status == :draft
    end

    test "REQ-003-6: submitting twice does nothing", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())
      {:ok, submitted} = Listings.submit_listing(scope, listing)

      assert {:error, :invalid_status} = Listings.submit_listing(scope, submitted)
      # even with the stale Draft copy
      assert {:error, :invalid_status} = Listings.submit_listing(scope, listing)

      assert Listings.get_my_listing!(scope, listing.id).submitted_at == submitted.submitted_at
      assert Listings.count_open_listings(scope) == 1
    end

    test "REQ-003-6: only a draft or rejected listing can be submitted", %{scope: scope} do
      for status <- [:published, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)
        assert {:error, :invalid_status} = Listings.submit_listing(scope, listing)
        assert Listings.get_my_listing!(scope, listing.id).status == status
      end
    end

    test "REQ-003-2: change business details", %{scope: scope} do
      live = listing_in_status_fixture(scope, :published)
      old_name = scope.user.business_name
      assert live.business_name == old_name

      {:ok, user} =
        Jairojobs.Accounts.update_business_details(scope, %{
          business_name: "Renamed Café",
          business_about: "New owners."
        })

      scope = Scope.for_user(user)
      draft = listing_fixture(scope, complete_listing_attrs())
      assert {:ok, submitted} = Listings.submit_listing(scope, draft)

      assert submitted.business_name == "Renamed Café"
      assert submitted.business_about == "New owners."
      assert Listings.get_my_listing!(scope, live.id).business_name == old_name
    end

    test "REQ-003-2: the business details copied are the stored ones, not a stale scope's", %{
      scope: stale_scope
    } do
      draft = listing_fixture(stale_scope, complete_listing_attrs())

      {:ok, _user} =
        Jairojobs.Accounts.update_business_details(stale_scope, %{business_name: "Renamed Café"})

      assert {:ok, submitted} = Listings.submit_listing(stale_scope, draft)
      assert submitted.business_name == "Renamed Café"
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_fixture(employer_scope_fixture(), complete_listing_attrs())

      assert {:error, :not_found} = Listings.submit_listing(scope, theirs)
      assert {:error, :not_found} = Listings.submit_listing(admin_poster_scope_fixture(), theirs)

      for other <- non_poster_scopes() do
        assert {:error, :unauthorized} = Listings.submit_listing(other, theirs)
      end

      assert Repo.get!(Listing, theirs.id).status == :draft
    end
  end

  describe "withdraw_listing/2" do
    test "REQ-003-7: withdraw", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())
      {:ok, pending} = Listings.submit_listing(scope, listing)

      assert {:ok, withdrawn} = Listings.withdraw_listing(scope, pending)
      assert withdrawn.status == :draft
      assert withdrawn.submitted_at == nil
      assert Listings.count_open_listings(scope) == 0

      assert {:ok, %Listing{title: "Senior barista"}} =
               Listings.update_listing(scope, withdrawn, %{title: "Senior barista"})
    end

    test "REQ-003-7: only pending listings can be withdrawn", %{scope: scope} do
      for status <- [:draft, :published, :rejected, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)

        assert {:error, :invalid_status} = Listings.withdraw_listing(scope, listing)
        assert Listings.get_my_listing!(scope, listing.id).status == status
      end
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_in_status_fixture(employer_scope_fixture(), :pending)

      assert {:error, :not_found} = Listings.withdraw_listing(scope, theirs)

      assert {:error, :not_found} =
               Listings.withdraw_listing(admin_poster_scope_fixture(), theirs)

      for other <- non_poster_scopes() do
        assert {:error, :unauthorized} = Listings.withdraw_listing(other, theirs)
      end

      assert Repo.get!(Listing, theirs.id).status == :pending
    end
  end

  describe "resubmitting a rejected listing" do
    test "REQ-003-8: see the reason", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())
      set_listing_status(listing, :rejected, reason: "Salary looks like a typo")

      rejected = Listings.get_my_listing!(scope, listing.id)
      assert rejected.status == :rejected
      assert rejected.rejection_reason == "Salary looks like a typo"
    end

    test "REQ-003-8: fix and resubmit", %{scope: scope} do
      rejected = listing_in_status_fixture(scope, :rejected)
      {:ok, fixed} = Listings.update_listing(scope, rejected, %{salary_max: 18_000})

      assert {:ok, resubmitted} = Listings.submit_listing(scope, fixed)
      assert resubmitted.status == :pending
      assert resubmitted.rejection_reason == nil
      assert resubmitted.salary_max == 18_000
      assert DateTime.compare(resubmitted.submitted_at, rejected.submitted_at) == :gt
    end

    test "REQ-003-8: a rejected listing may be resubmitted without changes", %{scope: scope} do
      rejected = listing_in_status_fixture(scope, :rejected)

      assert {:ok, %Listing{status: :pending, rejection_reason: nil}} =
               Listings.submit_listing(scope, rejected)
    end

    test "REQ-003-8: resubmit follows the same checks", %{scope: scope} do
      rejected = listing_in_status_fixture(scope, :rejected)
      {:ok, incomplete} = Listings.update_listing(scope, rejected, %{area: ""})

      assert {:error, {:incomplete, [:area]}} = Listings.submit_listing(scope, incomplete)

      {:ok, complete} = Listings.update_listing(scope, incomplete, %{area: "Matina"})

      for status <- [:pending, :published, :published],
          do: listing_in_status_fixture(scope, status)

      assert {:error, :limit_reached} = Listings.submit_listing(scope, complete)

      stored = Listings.get_my_listing!(scope, rejected.id)
      assert stored.status == :rejected
      assert stored.rejection_reason == rejected.rejection_reason
    end
  end

  describe "close_listing/2" do
    test "REQ-003-9: close", %{scope: scope} do
      live = listing_in_status_fixture(scope, :published)

      assert {:ok, closed} = Listings.close_listing(scope, live)
      assert closed.status == :closed
      assert %DateTime{} = closed.closed_at
      assert Enum.map(Listings.list_my_listings(scope), & &1.id) == [live.id]
    end

    test "REQ-003-9: only live listings can be closed", %{scope: scope} do
      for status <- [:draft, :pending, :rejected, :closed, :taken_down] do
        listing = listing_in_status_fixture(scope, status)

        assert {:error, :invalid_status} = Listings.close_listing(scope, listing)
        assert Listings.get_my_listing!(scope, listing.id).status == status
      end
    end

    test "REQ-003-9: a closed listing has no way back", %{scope: scope} do
      {:ok, closed} = Listings.close_listing(scope, listing_in_status_fixture(scope, :published))

      assert {:error, :invalid_status} = Listings.submit_listing(scope, closed)
      assert {:error, :invalid_status} = Listings.withdraw_listing(scope, closed)
      assert {:error, :locked} = Listings.update_listing(scope, closed, %{title: "Reopened"})
      assert {:error, :locked} = Listings.delete_listing(scope, closed)
    end

    test "REQ-003-12: closing or withdrawing frees a place", %{scope: scope} do
      live = listing_in_status_fixture(scope, :published)
      pending = listing_in_status_fixture(scope, :pending)
      listing_in_status_fixture(scope, :published)
      first = listing_fixture(scope, complete_listing_attrs())
      second = listing_fixture(scope, complete_listing_attrs())

      assert {:error, :limit_reached} = Listings.submit_listing(scope, first)

      {:ok, _closed} = Listings.close_listing(scope, live)
      assert {:ok, _pending} = Listings.submit_listing(scope, first)
      assert {:error, :limit_reached} = Listings.submit_listing(scope, second)

      {:ok, _draft} = Listings.withdraw_listing(scope, pending)
      assert {:ok, _pending} = Listings.submit_listing(scope, second)
    end

    test "REQ-003-14: another employer's listing is not found", %{scope: scope} do
      theirs = listing_in_status_fixture(employer_scope_fixture(), :published)

      assert {:error, :not_found} = Listings.close_listing(scope, theirs)
      assert {:error, :not_found} = Listings.close_listing(admin_poster_scope_fixture(), theirs)

      for other <- non_poster_scopes() do
        assert {:error, :unauthorized} = Listings.close_listing(other, theirs)
      end

      assert Repo.get!(Listing, theirs.id).status == :published
    end
  end

  describe "free-tier limit" do
    defp open_listings(scope, statuses) do
      for status <- statuses, do: listing_in_status_fixture(scope, status)
    end

    test "the limit is 3 for an employer and none for an admin", %{scope: scope} do
      assert Listings.open_listing_limit(scope) == 3
      assert Listings.open_listing_limit(admin_poster_scope_fixture()) == :unlimited
    end

    test "REQ-003-12: within the limit", %{scope: scope} do
      open_listings(scope, [:pending, :published])
      draft = listing_fixture(scope, complete_listing_attrs())

      assert {:ok, %Listing{status: :pending}} = Listings.submit_listing(scope, draft)
      assert Listings.count_open_listings(scope) == 3
    end

    test "REQ-003-12: limit reached", %{scope: scope} do
      open_listings(scope, [:pending, :published, :published])
      draft = listing_fixture(scope, complete_listing_attrs())

      assert {:error, :limit_reached} = Listings.submit_listing(scope, draft)
      assert Listings.get_my_listing!(scope, draft.id).status == :draft
      assert Listings.count_open_listings(scope) == 3
    end

    test "REQ-003-12: drafts are not limited", %{scope: scope} do
      open_listings(scope, [:pending, :published, :published])

      assert {:ok, %Listing{status: :draft}} =
               Listings.create_listing(scope, complete_listing_attrs())

      assert {:ok, %Listing{status: :draft}} = Listings.create_listing(scope, %{title: "Barista"})
    end

    test "REQ-003-12: only pending and published listings count", %{scope: scope} do
      open_listings(scope, [:draft, :rejected, :closed, :taken_down])
      assert Listings.count_open_listings(scope) == 0

      open_listings(scope, [:pending, :published])
      assert Listings.count_open_listings(scope) == 2

      open_listings(employer_scope_fixture(), [:pending, :published, :published])
      assert Listings.count_open_listings(scope) == 2
    end

    test "REQ-003-12: admins are not limited" do
      scope = admin_poster_scope_fixture()
      open_listings(scope, [:pending, :published, :published])
      draft = listing_fixture(scope, complete_listing_attrs())

      assert {:ok, %Listing{status: :pending}} = Listings.submit_listing(scope, draft)
      assert Listings.count_open_listings(scope) == 4
    end

    test "REQ-003-12: nothing is counted for a scope that may not post" do
      for scope <- non_poster_scopes() do
        assert Listings.count_open_listings(scope) == 0
      end
    end
  end

  describe "regions and listings" do
    test "REQ-002-4: hidden region keeps its data", %{scope: scope} do
      region = region_fixture()
      statuses = [:draft, :pending, :published, :rejected, :closed, :taken_down]

      before =
        for status <- statuses do
          listing_in_status_fixture(scope, status, region_id: region.id)
        end

      {:ok, hidden} = Jairojobs.Regions.hide_region(admin_scope_fixture(), region)
      refute hidden.active

      for listing <- before do
        stored = Listings.get_my_listing!(scope, listing.id)
        assert stored.status == listing.status
        assert stored.region_id == region.id
        assert stored.updated_at == listing.updated_at
      end

      assert Jairojobs.Regions.get_region_by_slug(region.slug).id == region.id
    end
  end

  describe "change_listing/2" do
    test "returns a changeset for the form" do
      assert %Ecto.Changeset{valid?: true} =
               Listings.change_listing(%Listing{}, %{title: "Barista"})

      assert %Ecto.Changeset{valid?: false} = Listings.change_listing(%Listing{}, %{title: ""})
    end
  end

  describe "database constraints" do
    defp raw_update(listing, set) do
      Repo.query!("UPDATE listings SET #{set} WHERE id = $1", [Ecto.UUID.dump!(listing.id)])
    end

    test "REQ-003-4: the salary range is guarded by the database", %{scope: scope} do
      listing = listing_fixture(scope)

      for set <- [
            "salary_min_centavos = 1400000",
            "salary_min_centavos = 1600000, salary_max_centavos = 1400000",
            "salary_min_centavos = 99900, salary_max_centavos = 1400000",
            "salary_min_centavos = 1400000, salary_max_centavos = 100000100",
            "salary_min_centavos = 1400050, salary_max_centavos = 1600000"
          ] do
        assert_raise Postgrex.Error, ~r/listings_salary_check/, fn -> raw_update(listing, set) end
      end
    end

    test "the status is guarded by the database", %{scope: scope} do
      listing = listing_fixture(scope, complete_listing_attrs())

      assert_raise Postgrex.Error, ~r/listings_status_check/, fn ->
        raw_update(listing, "status = 'expired', business_name = 'Kape Isla'")
      end
    end

    test "REQ-003-4: an incomplete listing cannot leave Draft, whoever changes the status", %{
      scope: scope
    } do
      title_only = listing_fixture(scope)
      no_business = listing_fixture(scope, complete_listing_attrs())

      for listing <- [title_only, no_business],
          status <- ~w(pending published closed taken_down) do
        assert_raise Postgrex.Error, ~r/listings_complete_unless_unsubmitted/, fn ->
          raw_update(listing, "status = '#{status}'")
        end
      end

      # a rejected listing may be incomplete again while its owner fixes it
      raw_update(title_only, "status = 'rejected'")
    end

    test "the employment type is guarded by the database", %{scope: scope} do
      listing = listing_fixture(scope)

      assert_raise Postgrex.Error, ~r/listings_employment_type_check/, fn ->
        raw_update(listing, "employment_type = 'freelance'")
      end
    end
  end
end
