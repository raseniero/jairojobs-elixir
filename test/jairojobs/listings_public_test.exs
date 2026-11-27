defmodule Jairojobs.ListingsPublicTest do
  @moduledoc """
  The public side of listings (spec 005): a listing's public address, and what
  the public may read. Listings reach each status through the real context
  functions.
  """
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Listings.ListingAddress
  alias Jairojobs.Regions

  @reason "Not suitable for the board as it is written."

  defp owner_url, do: &"https://jairojobs.test/my/listings/#{&1.id}"

  defp reload(%Listing{id: id}), do: Repo.get!(Listing, id)

  # A complete listing with `title` in `region`, submitted: Pending approval.
  defp pending(scope, title, region, attrs \\ %{}) do
    attrs = Map.merge(%{title: title, region_id: region.id}, Map.new(attrs))
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    {:ok, listing} = Listings.submit_listing(scope, listing, &admin_url/1)
    listing
  end

  defp approve(admin, listing) do
    {:ok, listing, _email} = Listings.approve_listing(admin, listing, owner_url())
    listing
  end

  defp published(scope, admin, title, region, attrs \\ %{}),
    do: approve(admin, pending(scope, title, region, attrs))

  # Every address `listing` has or had, as `{region slug, listing slug}`, oldest first.
  defp addresses(%Listing{id: id}) do
    Repo.all(
      from a in ListingAddress,
        join: r in assoc(a, :region),
        where: a.listing_id == ^id,
        order_by: [asc: a.inserted_at, asc: a.id],
        select: {r.slug, a.slug}
    )
  end

  setup do
    %{
      # An Admin owner has no limit on open listings (REQ-003-12).
      owner: admin_poster_scope_fixture(),
      admin: admin_scope_fixture(),
      davao: region_fixture(name: "Davao City"),
      cebu: region_fixture(name: "Cebu")
    }
  end

  describe "a listing's public address (REQ-005-6)" do
    test "REQ-005-6: The address is made at approval", %{owner: owner, admin: admin, davao: davao} do
      waiting = pending(owner, "Barista (full-time)", davao)
      assert waiting.slug == nil

      listing = approve(admin, waiting)

      assert listing.slug == "barista-full-time"
      assert listing.region.slug == "davao-city"
      assert reload(listing).slug == "barista-full-time"
      assert addresses(listing) == [{"davao-city", "barista-full-time"}]
    end

    test "REQ-005-6: The same title in the same region gets a number",
         %{owner: owner, admin: admin, davao: davao} do
      first = published(owner, admin, "Barista (full-time)", davao)
      second = published(owner, admin, "Barista (full-time)", davao)
      third = published(employer_scope_fixture(), admin, "Barista (full-time)", davao)

      assert first.slug == "barista-full-time"
      assert second.slug == "barista-full-time-2"
      assert third.slug == "barista-full-time-3"
    end

    test "REQ-005-6: The same title in another region needs no number",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      in_davao = published(owner, admin, "Barista (full-time)", davao)
      in_cebu = published(owner, admin, "Barista (full-time)", cebu)

      assert in_davao.slug == "barista-full-time"
      assert in_cebu.slug == "barista-full-time"
      assert addresses(in_cebu) == [{"cebu", "barista-full-time"}]
    end

    test "REQ-005-6: A changed title keeps the address",
         %{owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          %{title: "Barista (full-time, weekends)", business_name: "Kape Isla Café"},
          owner_url()
        )

      assert edited.title == "Barista (full-time, weekends)"
      assert edited.slug == "barista-full-time"

      # A region's own slug never changes either (REQ-002-3), so its rename moves nothing.
      {:ok, renamed} = Regions.rename_region(admin, davao, %{name: "Davao"})
      assert renamed.slug == "davao-city"

      assert reload(listing).slug == "barista-full-time"
      assert addresses(listing) == [{"davao-city", "barista-full-time"}]
    end

    test "REQ-005-6: Unusual characters in a title", %{owner: owner, admin: admin, cebu: cebu} do
      listing = published(owner, admin, "Café Staff — ₱500/day!!", cebu)

      assert listing.slug == "cafe-staff-500-day"
      assert addresses(listing) == [{"cebu", "cafe-staff-500-day"}]
    end

    test "REQ-005-6: An unpublished listing has no public address",
         %{owner: owner, admin: admin, davao: davao} do
      draft = listing_fixture(owner, complete_listing_attrs(region_id: davao.id))
      waiting = pending(owner, "Cashier (weekends)", davao)

      {:ok, rejected, _email} =
        Listings.reject_listing(
          admin,
          pending(owner, "Line cook (nights)", davao),
          %{reason: @reason},
          owner_url()
        )

      {:ok, withdrawn} = Listings.withdraw_listing(owner, pending(owner, "Dishwasher", davao))

      for listing <- [draft, waiting, rejected, withdrawn] do
        assert reload(listing).slug == nil
        assert addresses(listing) == []
      end

      assert Repo.aggregate(ListingAddress, :count) == 0
    end

    test "REQ-005-6: An address is never given to another listing",
         %{owner: owner, admin: admin, davao: davao} do
      closed = published(owner, admin, "Barista (full-time)", davao)
      {:ok, closed} = Listings.close_listing(owner, closed)

      # A closed listing keeps its address for good.
      assert closed.slug == "barista-full-time"
      assert addresses(closed) == [{"davao-city", "barista-full-time"}]

      second = published(owner, admin, "Barista (full-time)", davao)
      assert second.slug == "barista-full-time-2"

      # The same after a take-down.
      {:ok, taken_down, _email} =
        Listings.take_down_listing(admin, second, %{reason: @reason}, owner_url())

      assert taken_down.slug == "barista-full-time-2"

      third = published(owner, admin, "Barista (full-time)", davao)
      assert third.slug == "barista-full-time-3"
    end

    test "a title with nothing usable becomes \"job\", and approval is not refused",
         %{owner: owner, admin: admin, davao: davao} do
      assert published(owner, admin, "₱₱₱₱₱", davao).slug == "job"
      assert published(owner, admin, "— !!! —", davao).slug == "job-2"
    end

    test "the slug is made from the title as it is at the moment of approval",
         %{owner: owner, admin: admin, davao: davao} do
      waiting = pending(owner, "Barrista", davao)

      {:ok, fixed, _email} =
        Listings.update_listing_as_admin(admin, waiting, %{title: "Barista"}, owner_url())

      assert fixed.slug == nil
      assert approve(admin, fixed).slug == "barista"
    end

    test "a hidden region still refuses approval, and no address is written",
         %{owner: owner, admin: admin, davao: davao} do
      waiting = pending(owner, "Barista (full-time)", davao)
      {:ok, _hidden} = Regions.hide_region(admin, davao)

      assert {:error, :region_hidden} = Listings.approve_listing(admin, waiting, owner_url())

      assert %Listing{status: :pending, slug: nil} = reload(waiting)
      assert addresses(waiting) == []
    end

    test "the slug cannot be set through the Admin edit form",
         %{owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      for params <- [
            %{"slug" => "free-money", "title" => "Barista (weekends)"},
            %{slug: "free-money", area: "Lanang"}
          ] do
        {:ok, edited, _email} =
          Listings.update_listing_as_admin(admin, listing, params, owner_url())

        assert edited.slug == "barista-full-time"
      end

      waiting = pending(owner, "Cashier (weekends)", davao)

      {:ok, edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          waiting,
          %{"slug" => "free-money", "area" => "Lanang"},
          owner_url()
        )

      assert edited.slug == nil
    end

    test "nor through the Employer's form" do
      employer = employer_scope_fixture()

      {:ok, draft} =
        Listings.create_listing(employer, %{
          "title" => "Barista (full-time)",
          "slug" => "free-money"
        })

      assert draft.slug == nil

      {:ok, edited} =
        Listings.update_listing(employer, draft, %{"slug" => "free-money", "area" => "Matina"})

      assert edited.slug == nil
    end
  end

  describe "the database guards the addresses (REQ-005-6)" do
    setup %{owner: owner, admin: admin, davao: davao} do
      %{listing: published(owner, admin, "Barista (full-time)", davao)}
    end

    test "an address cannot be recorded for a second listing",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      other = published(owner, admin, "Cashier (weekends)", cebu)

      assert_raise Ecto.ConstraintError, ~r/listing_addresses_region_id_slug_index/, fn ->
        Repo.insert!(%ListingAddress{
          listing_id: other.id,
          region_id: davao.id,
          slug: "barista-full-time"
        })
      end
    end

    test "a listing cannot have two addresses in one region",
         %{listing: listing, davao: davao} do
      assert_raise Ecto.ConstraintError, ~r/listing_addresses_listing_id_region_id_index/, fn ->
        Repo.insert!(%ListingAddress{listing_id: listing.id, region_id: davao.id, slug: "other"})
      end
    end

    test "a slug must be lowercase letters, digits and single hyphens, at most 60",
         %{listing: listing, cebu: cebu} do
      for slug <-
            ["Barista", "barista--x", "-barista", "barista-", "café", "a b", ""] ++
              [String.duplicate("a", 61)] do
        assert_raise Ecto.ConstraintError, ~r/listing_addresses_slug_format/, fn ->
          Repo.insert!(%ListingAddress{listing_id: listing.id, region_id: cebu.id, slug: slug})
        end
      end

      assert %ListingAddress{} =
               Repo.insert!(%ListingAddress{
                 listing_id: listing.id,
                 region_id: cebu.id,
                 slug: String.duplicate("a", 60)
               })
    end

    test "a listing that has an address cannot be deleted from the database",
         %{listing: listing} do
      assert_raise Ecto.ConstraintError, ~r/listing_addresses_listing_id_fkey/, fn ->
        Repo.delete!(listing)
      end
    end
  end
end
