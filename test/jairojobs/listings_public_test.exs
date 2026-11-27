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

  alias Jairojobs.Accounts.Scope
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

  describe "list_public_listings/1 (REQ-005-1, REQ-005-2)" do
    defp titles({listings, _total}), do: Enum.map(listings, & &1.title)

    test "REQ-005-1: Other statuses are on no public list",
         %{owner: owner, admin: admin, davao: davao} do
      _draft =
        listing_fixture(owner, complete_listing_attrs(title: "A draft", region_id: davao.id))

      _waiting = pending(owner, "A pending one", davao)

      {:ok, _rejected, _email} =
        Listings.reject_listing(
          admin,
          pending(owner, "A rejected one", davao),
          %{reason: @reason},
          owner_url()
        )

      {:ok, _closed} =
        Listings.close_listing(owner, published(owner, admin, "A closed one", davao))

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published(owner, admin, "A taken down one", davao),
          %{reason: @reason},
          owner_url()
        )

      _published = published(owner, admin, "The published one", davao)

      # On the list of every region, and on their own region's list.
      assert {[%Listing{title: "The published one", status: :published}], 1} =
               Listings.list_public_listings()

      assert {[%Listing{title: "The published one"}], 1} =
               Listings.list_public_listings(region: davao)
    end

    test "nothing is listed when nothing is Published", %{owner: owner, davao: davao} do
      _waiting = pending(owner, "A pending one", davao)

      assert Listings.list_public_listings() == {[], 0}
      assert Listings.list_public_listings(region: davao) == {[], 0}
    end

    test "REQ-005-1: A hidden region does not hide a listing",
         %{owner: owner, admin: admin} do
      baguio = region_fixture(name: "Baguio")
      listing = published(owner, admin, "Barista (full-time)", baguio)
      {:ok, hidden} = Regions.hide_region(admin, baguio)

      assert {[%Listing{id: id, region: %{name: "Baguio", active: false}}], 1} =
               Listings.list_public_listings()

      assert id == listing.id

      # Its own list still holds it too (REQ-005-3).
      assert {[%Listing{id: ^id}], 1} = Listings.list_public_listings(region: hidden)
    end

    test "REQ-005-1: The owner's role does not matter", %{admin: admin, davao: davao} do
      owner = admin_poster_scope_fixture()
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, demoted} = Jairojobs.Accounts.demote_admin(Scope.system(), owner.user)
      assert demoted.role == :candidate

      assert {[%Listing{id: id}], 1} = Listings.list_public_listings()
      assert id == listing.id
    end

    test "REQ-005-2: Newest first", %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      # Made in one order, approved in another: only the time of approval counts.
      barista = published(owner, admin, "Barista", davao)
      cashier = published(owner, admin, "Cashier", cebu)
      cook = published(owner, admin, "Line cook", davao)

      approved_ago(cashier, 3, :hour)
      approved_ago(barista, 20, :minute)
      approved_ago(cook, 2, :day)

      assert titles(Listings.list_public_listings()) == ["Barista", "Cashier", "Line cook"]
      assert titles(Listings.list_public_listings(region: davao)) == ["Barista", "Line cook"]
    end

    test "two listings approved at the same instant keep one order",
         %{owner: owner, admin: admin, davao: davao} do
      first = published(owner, admin, "Barista", davao)
      second = published(owner, admin, "Cashier", davao)
      at = ~U[2026-11-20 08:00:00.000000Z]

      Repo.update_all(from(l in Listing, where: l.id in ^[first.id, second.id]),
        set: [published_at: at]
      )

      # The later id first: ids are time-ordered (ADR-0004).
      assert titles(Listings.list_public_listings()) == ["Cashier", "Barista"]
    end

    test "REQ-005-2: A long list is shown in parts", %{owner: owner, admin: admin, davao: davao} do
      for n <- 1..25 do
        owner
        |> published(admin, "Job number #{n}", davao)
        |> approved_ago(n, :hour)
      end

      assert {first, 25} = Listings.list_public_listings()
      assert Enum.map(first, & &1.title) == Enum.map(1..20, &"Job number #{&1}")

      assert {rest, 25} = Listings.list_public_listings(offset: 20)
      assert Enum.map(rest, & &1.title) == Enum.map(21..25, &"Job number #{&1}")

      assert {[], 25} = Listings.list_public_listings(offset: 40)

      assert {ten, 25} = Listings.list_public_listings(limit: 10, offset: 5)
      assert Enum.map(ten, & &1.title) == Enum.map(6..15, &"Job number #{&1}")
    end

    test "REQ-005-2: An edit does not move a listing",
         %{owner: owner, admin: admin, davao: davao} do
      cashier = owner |> published(admin, "Cashier", davao) |> approved_ago(3, :hour)
      _barista = owner |> published(admin, "Barista", davao) |> approved_ago(20, :minute)

      {:ok, edited, _email} =
        Listings.update_listing_as_admin(admin, cashier, %{area: "Lanang"}, owner_url())

      assert edited.published_at == cashier.published_at
      assert titles(Listings.list_public_listings()) == ["Barista", "Cashier"]
    end

    test "a region's list holds that region's listings only, and the count follows",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      published(owner, admin, "Barista", davao)
      published(owner, admin, "Cashier", davao)
      published(owner, admin, "Line cook", cebu)

      assert {[_, _], 2} = Listings.list_public_listings(region: davao)
      assert {[%Listing{title: "Line cook"}], 1} = Listings.list_public_listings(region: cebu)
      assert {[_, _, _], 3} = Listings.list_public_listings()

      assert {[], 0} = Listings.list_public_listings(region: region_fixture())
    end

    test "each listing comes with its region and its slug, ready for its address",
         %{owner: owner, admin: admin, cebu: cebu} do
      published(owner, admin, "Barista (full-time)", cebu)

      assert {[%Listing{slug: "barista-full-time", region: %{slug: "cebu", name: "Cebu"}}], 1} =
               Listings.list_public_listings()
    end
  end

  describe "search and type (REQ-005-4)" do
    defp search(words, opts \\ []),
      do: titles(Listings.list_public_listings([search: words] ++ opts))

    # The fixtures' usual "About the job" mentions a barista, which every search for
    # "barista" would then find. These listings say nothing a test searches for.
    @plain "A steady job with a friendly team in a busy neighbourhood shop."

    setup %{admin: admin, davao: davao} do
      kape_isla = admin_poster_scope_fixture(business_name: "Kape Isla")

      publish = fn title, attrs ->
        published(kape_isla, admin, title, davao, Map.merge(%{description: @plain}, attrs))
      end

      %{kape_isla: kape_isla, publish: publish}
    end

    test "REQ-005-4: Search by a word in the title", %{publish: publish} do
      publish.("Barista (full-time)", %{})
      publish.("Cashier", %{})

      assert search("barista") == ["Barista (full-time)"]
      assert search("cashier") == ["Cashier"]
    end

    test "REQ-005-4: Search finds the business and the area", %{publish: publish, admin: admin} do
      publish.("Barista (full-time)", %{area: "Matina"})

      other = admin_poster_scope_fixture(business_name: "Tindahan ni Aling Nena")

      published(other, admin, "Store attendant", region_fixture(),
        area: "Lanang",
        description: @plain
      )

      assert search("kape") == ["Barista (full-time)"]
      assert search("matina") == ["Barista (full-time)"]
      assert search("nena") == ["Store attendant"]
      assert search("lanang") == ["Store attendant"]
    end

    test "REQ-005-4: Search finds words in the listing's text", %{publish: publish} do
      publish.("Barista (full-time)", %{
        description:
          "Training provided; experience with espresso machines is a plus for this role.",
        requirements: "At least 18 years old\nWilling to work weekends",
        benefits: "Free meals on shift\nSSS, PhilHealth, Pag-IBIG"
      })

      publish.("Cashier", %{})

      # About the job, Requirements, Benefits.
      assert search("espresso") == ["Barista (full-time)"]
      assert search("weekends") == ["Barista (full-time)"]
      assert search("philhealth") == ["Barista (full-time)"]
    end

    test "REQ-005-4: Every word must be found", %{publish: publish} do
      publish.("Barista", %{area: "Matina"}) |> approved_ago(1, :hour)
      publish.("Barista", %{area: "Lanang"}) |> approved_ago(2, :hour)

      assert {[%Listing{area: "Matina"}], 1} =
               Listings.list_public_listings(search: "barista matina")

      # The words may be in different parts, in any order.
      assert {[%Listing{area: "Matina"}], 1} =
               Listings.list_public_listings(search: "matina kape barista")

      assert {[_, _], 2} = Listings.list_public_listings(search: "barista")
      assert {[], 0} = Listings.list_public_listings(search: "barista toril")
    end

    test "REQ-005-4: Capitals do not matter", %{publish: publish} do
      publish.("Barista (full-time)", %{})

      assert search("BARISTA") == ["Barista (full-time)"]
      assert search("bArIsTa") == ["Barista (full-time)"]
      assert search("KAPE isla") == ["Barista (full-time)"]
    end

    test "REQ-005-4: Filter by type", %{publish: publish} do
      publish.("A full-time job", %{employment_type: :full_time})
      publish.("A part-time job", %{employment_type: :part_time})

      assert {[%Listing{title: "A part-time job"}], 1} =
               Listings.list_public_listings(type: :part_time)

      assert {[%Listing{title: "A full-time job"}], 1} =
               Listings.list_public_listings(type: :full_time)

      assert {[], 0} = Listings.list_public_listings(type: :internship)

      # No type is any type.
      assert {[_, _], 2} = Listings.list_public_listings(type: nil)
    end

    test "REQ-005-4: Search and type together, inside a region",
         %{publish: publish, kape_isla: kape_isla, admin: admin, davao: davao, cebu: cebu} do
      publish.("Barista (weekends)", %{employment_type: :part_time})
      publish.("Barista (full-time)", %{employment_type: :full_time})
      publish.("Cashier (weekends)", %{employment_type: :part_time})

      published(kape_isla, admin, "Barista (evenings)", cebu,
        employment_type: :part_time,
        description: @plain
      )

      assert {[%Listing{title: "Barista (weekends)"}], 1} =
               Listings.list_public_listings(region: davao, search: "barista", type: :part_time)

      assert {[_, _], 2} = Listings.list_public_listings(search: "barista", type: :part_time)
    end

    test "REQ-005-4: An empty search is no search", %{publish: publish} do
      for title <- ["Barista", "Cashier", "Line cook"], do: publish.(title, %{})

      for nothing <- [nil, "", "   ", "\n\t "] do
        assert {[_, _, _], 3} = Listings.list_public_listings(search: nothing)
      end
    end

    test "the count follows the search", %{publish: publish} do
      for n <- 1..3, do: publish.("Barista number #{n}", %{})
      publish.("Cashier", %{})

      assert {[_, _, _], 3} = Listings.list_public_listings(search: "barista")
      assert {[_, _], 3} = Listings.list_public_listings(search: "barista", limit: 2)
    end

    test "results stay newest first, whatever matched best", %{publish: publish} do
      publish.("Barista barista barista", %{}) |> approved_ago(3, :day)
      publish.("Line cook", %{description: String.duplicate("We also need a barista. ", 3)})

      assert search("barista") == ["Line cook", "Barista barista barista"]
    end

    test "a search never finds a listing that is not Published",
         %{kape_isla: kape_isla, admin: admin, davao: davao} do
      _waiting = pending(kape_isla, "Barista (pending)", davao)

      {:ok, _closed} =
        Listings.close_listing(kape_isla, published(kape_isla, admin, "Barista (closed)", davao))

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published(kape_isla, admin, "Barista (taken down)", davao),
          %{reason: @reason},
          owner_url()
        )

      assert search("barista") == []
      assert {[], 0} = Listings.list_public_listings(type: :full_time)
    end

    test "a word is a whole word: part of one is not promised, and not found",
         %{publish: publish} do
      publish.("Delivery drivers wanted", %{})

      assert search("drivers") == ["Delivery drivers wanted"]
      assert search("driver") == []
      assert search("deliv") == []
    end

    test "punctuation around a word does not get in the way", %{publish: publish} do
      publish.("Barista (full-time)", %{requirements: "Customer-facing; cash handling."})

      assert search("full-time") == ["Barista (full-time)"]
      assert search("(barista)") == ["Barista (full-time)"]
      assert search("handling") == ["Barista (full-time)"]
      assert search("cash, handling!") == ["Barista (full-time)"]
    end

    test "the business name searched is the listing's own copy",
         %{publish: publish, admin: admin} do
      listing = publish.("Barista (full-time)", %{})

      {:ok, _edited, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          %{business_name: "Bean Scene"},
          owner_url()
        )

      assert search("bean") == ["Barista (full-time)"]
      assert search("kape") == []
    end

    test "words past 100 characters are cut", %{publish: publish} do
      publish.("Barista (full-time)", %{})

      # The 101st character onwards is a word no listing has. Cut off, it changes nothing.
      long = String.pad_trailing("barista", 100) <> "astronaut"
      assert String.length(long) == 109

      assert search(long) == ["Barista (full-time)"]
      assert search("barista astronaut") == []
    end

    test "words made only of punctuation find nothing", %{publish: publish} do
      publish.("Barista (full-time)", %{})

      for words <- ["!!!", "—", "( )", "..."] do
        assert search(words) == []
      end
    end

    test "characters that mean something to the database are harmless", %{
      publish: publish,
      admin: admin
    } do
      publish.("Barista (full-time)", %{benefits: "100% of tips are yours"})
      obrien = admin_poster_scope_fixture(business_name: "O'Brien's Pub")
      published(obrien, admin, "Bartender", region_fixture(), description: @plain)

      # Not wildcards, not quotes, not escapes, not operators: only words, or nothing.
      assert search("%") == []
      assert search("_") == []
      assert search("\\") == []
      assert search("'") == []
      assert search("barista & cashier") == []
      assert search("barista | cashier") == []
      assert search("!barista") == ["Barista (full-time)"]
      assert search("100%") == ["Barista (full-time)"]
      assert search("o'brien") == ["Bartender"]
      assert search("'; DROP TABLE listings; --") == []
      assert search("bar\0ista") == []

      assert {[_, _], 2} = Listings.list_public_listings()
    end
  end

  describe "search_words/1 (REQ-005-4)" do
    test "trims, and cuts at 100 characters" do
      assert Listings.search_words("  barista  ") == "barista"
      assert Listings.search_words("barista   matina") == "barista   matina"

      cut = Listings.search_words(String.duplicate("ab ", 60))
      assert String.length(cut) <= 100
      assert String.starts_with?(cut, "ab ab")
      refute String.ends_with?(cut, " ")
    end

    test "nothing typed, or only spaces, is no search" do
      for nothing <- [nil, "", "   ", "\n\t "] do
        assert Listings.search_words(nothing) == nil
      end
    end

    test "counts characters, not bytes" do
      assert Listings.search_words(String.duplicate("ñ", 150)) == String.duplicate("ñ", 100)
    end

    test "anything that is not text is no search" do
      assert Listings.search_words(%{"a" => "b"}) == nil
      assert Listings.search_words(["barista"]) == nil
      assert Listings.search_words(42) == nil
    end
  end

  describe "resolve_public_address/2 (REQ-005-6, REQ-005-7)" do
    defp move_to(admin, listing, region) do
      {:ok, moved, _email} =
        Listings.update_listing_as_admin(admin, listing, %{region_id: region.id}, owner_url())

      moved
    end

    setup %{owner: owner, admin: admin, davao: davao} do
      %{listing: published(owner, admin, "Barista (full-time)", davao)}
    end

    test "the current address of a Published listing gives the listing, with its region",
         %{listing: listing} do
      assert {:ok, %Listing{} = found} =
               Listings.resolve_public_address("davao-city", "barista-full-time")

      assert found.id == listing.id
      assert found.status == :published
      assert found.region.name == "Davao City"
    end

    test "a Published listing in a hidden region is still found",
         %{admin: admin, davao: davao, listing: listing} do
      {:ok, _hidden} = Regions.hide_region(admin, davao)

      assert {:ok, %Listing{id: id, region: %{active: false}}} =
               Listings.resolve_public_address("davao-city", "barista-full-time")

      assert id == listing.id
    end

    test "an earlier address answers with the current one",
         %{admin: admin, cebu: cebu, listing: listing} do
      moved = move_to(admin, listing, cebu)

      assert Listings.resolve_public_address("davao-city", "barista-full-time") ==
               {:moved, %{region_slug: "cebu", slug: "barista-full-time"}}

      assert {:ok, %Listing{id: id}} =
               Listings.resolve_public_address("cebu", "barista-full-time")

      assert id == moved.id
    end

    test "every earlier address answers with the current one, and a numbered one too",
         %{owner: owner, admin: admin, cebu: cebu, listing: listing} do
      manila = region_fixture(name: "Metro Manila")
      _in_manila = published(owner, admin, "Barista (full-time)", manila)

      listing |> then(&move_to(admin, &1, cebu)) |> then(&move_to(admin, &1, manila))

      current = %{region_slug: "metro-manila", slug: "barista-full-time-2"}

      assert Listings.resolve_public_address("davao-city", "barista-full-time") ==
               {:moved, current}

      assert Listings.resolve_public_address("cebu", "barista-full-time") == {:moved, current}

      assert {:ok, %Listing{id: id}} =
               Listings.resolve_public_address("metro-manila", "barista-full-time-2")

      assert id == listing.id
    end

    test "a listing moved back is found at its first address again, and the other forwards",
         %{admin: admin, davao: davao, cebu: cebu, listing: listing} do
      listing |> then(&move_to(admin, &1, cebu)) |> then(&move_to(admin, &1, davao))

      assert {:ok, %Listing{}} =
               Listings.resolve_public_address("davao-city", "barista-full-time")

      assert Listings.resolve_public_address("cebu", "barista-full-time") ==
               {:moved, %{region_slug: "davao-city", slug: "barista-full-time"}}
    end

    test "REQ-005-7: Nothing of the listing is shown",
         %{owner: owner, admin: admin, davao: davao, listing: listing} do
      {:ok, closed} = Listings.close_listing(owner, listing)

      {:ok, taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published(owner, admin, "Cashier (weekends)", davao),
          %{reason: @reason},
          owner_url()
        )

      for {slug, gone} <- [{"barista-full-time", closed}, {"cashier-weekends", taken_down}] do
        assert {:gone, answer} = Listings.resolve_public_address("davao-city", slug)

        # Only what the page needs: where to send the visitor, and whose listing it is
        # so the owner and Admins can be given their link. No title, text or reason, and
        # nothing that tells a close from a take-down.
        assert answer == %{id: gone.id, user_id: owner.user.id, region: davao}
        assert answer |> Map.keys() |> Enum.sort() == [:id, :region, :user_id]
      end
    end

    test "the earlier address of a listing that was moved and then closed forwards, too",
         %{owner: owner, admin: admin, cebu: cebu, listing: listing} do
      moved = move_to(admin, listing, cebu)
      {:ok, _closed} = Listings.close_listing(owner, moved)

      assert Listings.resolve_public_address("davao-city", "barista-full-time") ==
               {:moved, %{region_slug: "cebu", slug: "barista-full-time"}}

      assert {:gone, %{id: id, region: %{slug: "cebu"}}} =
               Listings.resolve_public_address("cebu", "barista-full-time")

      assert id == listing.id
    end

    test "an address that never was a listing is not found",
         %{owner: owner, davao: davao, listing: listing} do
      _waiting = pending(owner, "Cashier (weekends)", davao)

      for {region, slug} <- [
            {"davao-city", "no-such-job"},
            # A listing that is not approved yet has no address.
            {"davao-city", "cashier-weekends"},
            # The right slug in the wrong region, and an unknown region.
            {"cebu", "barista-full-time"},
            {"atlantis", "barista-full-time"},
            # The id is never an address (constitution §4.8).
            {"davao-city", listing.id},
            {listing.region_id, listing.id},
            # Not slugs at all.
            {"davao-city", "Barista-Full-Time"},
            {"davao-city", "barista full time"},
            {"davao-city", "barista-full-time\0"},
            {"davao-city", ""},
            {"", "barista-full-time"},
            {"davao-city", "%"},
            {"davao-city", "' OR 1=1 --"}
          ] do
        assert Listings.resolve_public_address(region, slug) == :not_found
      end

      assert Listings.resolve_public_address(nil, "barista-full-time") == :not_found
      assert Listings.resolve_public_address("davao-city", %{"a" => "b"}) == :not_found
    end
  end

  describe "list_public_addresses/0 (REQ-005-9)" do
    test "the address of every Published listing, and of nothing else",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      barista = owner |> published(admin, "Barista (full-time)", davao) |> approved_ago(2, :hour)
      cashier = owner |> published(admin, "Cashier (weekends)", cebu) |> approved_ago(1, :hour)

      _draft = listing_fixture(owner, complete_listing_attrs(region_id: davao.id))
      _waiting = pending(owner, "A pending one", davao)

      {:ok, _closed} =
        Listings.close_listing(owner, published(owner, admin, "A closed one", davao))

      {:ok, _taken_down, _email} =
        Listings.take_down_listing(
          admin,
          published(owner, admin, "A taken down one", davao),
          %{reason: @reason},
          owner_url()
        )

      # Newest approval first, each with the time it last changed.
      assert Listings.list_public_addresses() == [
               %{
                 region_slug: "cebu",
                 slug: "cashier-weekends",
                 updated_at: reload(cashier).updated_at
               },
               %{
                 region_slug: "davao-city",
                 slug: "barista-full-time",
                 updated_at: reload(barista).updated_at
               }
             ]
    end

    test "a Published listing in a hidden region is included; an earlier address is not",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, _moved, _email} =
        Listings.update_listing_as_admin(admin, listing, %{region_id: cebu.id}, owner_url())

      {:ok, _hidden} = Regions.hide_region(admin, cebu)

      assert [%{region_slug: "cebu", slug: "barista-full-time"}] =
               Listings.list_public_addresses()
    end

    test "nothing when nothing is Published" do
      assert Listings.list_public_addresses() == []
    end
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

  describe "an Admin moves a Published listing to another region (REQ-005-6)" do
    defp move(admin, listing, region, more \\ %{}) do
      {:ok, moved, _email} =
        Listings.update_listing_as_admin(
          admin,
          listing,
          Map.merge(%{region_id: region.id}, more),
          owner_url()
        )

      moved
    end

    test "REQ-005-6: Moving to another region forwards the old address",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      moved = move(admin, listing, cebu)

      # The address follows the listing: the same slug, in the new region.
      assert moved.region.slug == "cebu"
      assert moved.slug == "barista-full-time"
      assert %Listing{slug: "barista-full-time", region_id: region_id} = reload(listing)
      assert region_id == cebu.id

      # The earlier address stays the listing's own, which is what makes it forward.
      assert addresses(listing) == [
               {"davao-city", "barista-full-time"},
               {"cebu", "barista-full-time"}
             ]
    end

    test "REQ-005-6: An earlier address is not given to another listing either",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      moved =
        owner |> published(admin, "Barista (full-time)", davao) |> then(&move(admin, &1, cebu))

      newcomer = published(owner, admin, "Barista (full-time)", davao)

      assert newcomer.slug == "barista-full-time-2"
      assert addresses(newcomer) == [{"davao-city", "barista-full-time-2"}]
      assert {"davao-city", "barista-full-time"} in addresses(moved)
    end

    test "a listing moved back returns to the address it had there",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      # Meanwhile nobody can take its Davao address, however many are approved there.
      away = move(admin, listing, cebu)
      _newcomer = published(owner, admin, "Barista (full-time)", davao)

      back = move(admin, away, davao)

      assert back.slug == "barista-full-time"
      assert back.region.slug == "davao-city"

      # No third address: one per region, for good.
      assert addresses(listing) == [
               {"davao-city", "barista-full-time"},
               {"cebu", "barista-full-time"}
             ]

      # And away again: the Cebu address is still its own.
      assert move(admin, back, cebu).slug == "barista-full-time"
      assert length(addresses(listing)) == 2
    end

    test "a move into a region where its slug is taken gets the next free number there",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      _in_cebu = published(owner, admin, "Barista (full-time)", cebu)
      listing = published(owner, admin, "Barista (full-time)", davao)

      moved = move(admin, listing, cebu)

      assert moved.slug == "barista-full-time-2"

      # Moved back, it has its unnumbered Davao address again.
      assert move(admin, moved, davao).slug == "barista-full-time"

      assert addresses(listing) == [
               {"davao-city", "barista-full-time"},
               {"cebu", "barista-full-time-2"}
             ]
    end

    test "a listing moved across three regions keeps all three addresses",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      manila = region_fixture(name: "Metro Manila")
      listing = published(owner, admin, "Barista (full-time)", davao)

      moved = listing |> then(&move(admin, &1, cebu)) |> then(&move(admin, &1, manila))

      assert moved.region.slug == "metro-manila"

      assert addresses(listing) == [
               {"davao-city", "barista-full-time"},
               {"cebu", "barista-full-time"},
               {"metro-manila", "barista-full-time"}
             ]
    end

    test "the slug comes from the address it has, not from a title changed in the same edit",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      moved = move(admin, listing, cebu, %{title: "Head barista"})

      assert moved.title == "Head barista"
      assert moved.slug == "barista-full-time"
    end

    test "moving a Pending listing writes no address",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      waiting = pending(owner, "Barista (full-time)", davao)

      moved = move(admin, waiting, cebu)

      assert moved.slug == nil
      assert addresses(waiting) == []

      # Its address is made where it is when it is approved.
      approved = approve(admin, moved)
      assert addresses(approved) == [{"cebu", "barista-full-time"}]
    end

    test "an edit that keeps the region writes no address",
         %{owner: owner, admin: admin, davao: davao} do
      listing = published(owner, admin, "Barista (full-time)", davao)

      {:ok, edited, _email} =
        Listings.update_listing_as_admin(admin, listing, %{area: "Lanang"}, owner_url())

      assert edited.slug == "barista-full-time"
      assert addresses(listing) == [{"davao-city", "barista-full-time"}]
    end

    test "a move that is refused writes no address",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu} do
      listing = published(owner, admin, "Barista (full-time)", davao)
      {:ok, _hidden} = Regions.hide_region(admin, cebu)

      # A hidden region, and a field that is not valid alongside a good region.
      assert {:error, %Ecto.Changeset{}} =
               Listings.update_listing_as_admin(
                 admin,
                 listing,
                 %{region_id: cebu.id},
                 owner_url()
               )

      manila = region_fixture(name: "Metro Manila")

      assert {:error, %Ecto.Changeset{}} =
               Listings.update_listing_as_admin(
                 admin,
                 listing,
                 %{region_id: manila.id, area: ""},
                 owner_url()
               )

      assert %Listing{slug: "barista-full-time", region_id: region_id} = reload(listing)
      assert region_id == davao.id
      assert addresses(listing) == [{"davao-city", "barista-full-time"}]
    end

    test "the email about the edit names the region, not the address",
         %{admin: admin, davao: davao, cebu: cebu} do
      employer = employer_scope_fixture()
      listing = published(employer, admin, "Barista (full-time)", davao)
      flush_emails()

      assert {:ok, _moved, :sent} =
               Listings.update_listing_as_admin(
                 admin,
                 listing,
                 %{region_id: cebu.id},
                 owner_url()
               )

      assert_received {:email, email}
      assert email.text_body =~ "  - Region\n"
      refute email.text_body =~ "slug"
      refute email.text_body =~ "ddress"
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

    # Straight to the table, past every changeset: what the database itself refuses.
    defp raw_update(%Listing{id: id}, set, params \\ []) do
      Repo.query!(
        "UPDATE listings SET #{set} WHERE id = $#{length(params) + 1}",
        params ++ [Ecto.UUID.dump!(id)]
      )
    end

    test "a listing has a slug exactly when it has been approved",
         %{owner: owner, davao: davao, listing: listing} do
      draft = listing_fixture(owner, complete_listing_attrs(region_id: davao.id))
      waiting = pending(owner, "Cashier (weekends)", davao)

      for unapproved <- [draft, waiting] do
        assert_raise Postgrex.Error, ~r/listings_slug_iff_approved/, fn ->
          raw_update(unapproved, "slug = 'cashier-weekends'")
        end
      end

      assert_raise Postgrex.Error, ~r/listings_slug_iff_approved/, fn ->
        raw_update(listing, "slug = NULL")
      end

      {:ok, closed} = Listings.close_listing(owner, listing)

      assert_raise Postgrex.Error, ~r/listings_slug_iff_approved/, fn ->
        raw_update(closed, "slug = NULL")
      end
    end

    test "a listing's current address must be one of its own recorded addresses",
         %{owner: owner, admin: admin, davao: davao, cebu: cebu, listing: listing} do
      other = published(owner, admin, "Cashier (weekends)", davao)
      assert other.slug == "cashier-weekends"

      # A slug nobody has, another listing's slug, and a region it has no address in.
      assert_raise Postgrex.Error, ~r/listings_current_address_fkey/, fn ->
        raw_update(listing, "slug = 'something-else'")
      end

      assert_raise Postgrex.Error, ~r/listings_current_address_fkey/, fn ->
        raw_update(listing, "slug = 'cashier-weekends'")
      end

      assert_raise Postgrex.Error, ~r/listings_current_address_fkey/, fn ->
        raw_update(listing, "region_id = $1", [Ecto.UUID.dump!(cebu.id)])
      end

      # With the address recorded there first, the same move is accepted.
      Repo.insert!(%ListingAddress{listing_id: listing.id, region_id: cebu.id, slug: "barista"})
      raw_update(listing, "region_id = $1, slug = 'barista'", [Ecto.UUID.dump!(cebu.id)])

      assert %Listing{slug: "barista"} = reload(listing)
    end

    test "a listing's current address cannot be removed", %{listing: listing} do
      assert_raise Postgrex.Error, ~r/listings_current_address_fkey/, fn ->
        Repo.delete_all(from a in ListingAddress, where: a.listing_id == ^listing.id)
      end
    end

    test "a listing that has an address cannot be deleted from the database",
         %{listing: listing} do
      assert_raise Ecto.ConstraintError, ~r/listing_addresses_listing_id_fkey/, fn ->
        Repo.delete!(listing)
      end
    end
  end
end
