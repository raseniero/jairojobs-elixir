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

    test "the employment type is guarded by the database", %{scope: scope} do
      listing = listing_fixture(scope)

      assert_raise Postgrex.Error, ~r/listings_employment_type_check/, fn ->
        raw_update(listing, "employment_type = 'freelance'")
      end
    end
  end
end
