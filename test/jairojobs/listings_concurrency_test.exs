defmodule Jairojobs.ListingsConcurrencyTest do
  # Not async, and outside the usual sandbox (constitution §3.5): these tests need real
  # database connections racing each other. Inside the sandbox the tasks would share one
  # transaction and the row locks in `Jairojobs.Listings` would prove nothing. Everything
  # they commit is deleted again in `on_exit`.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Jairojobs.Accounts.User
  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.ListingsFixtures
  alias Jairojobs.Regions.Region
  alias Jairojobs.Repo

  setup do
    users_before = unboxed(fn -> Repo.all(from u in User, select: u.id) end)
    regions_before = unboxed(fn -> Repo.all(from r in Region, select: r.id) end)

    on_exit(fn ->
      unboxed(fn ->
        # A listing and its public addresses refer to each other (spec 005), so the
        # database refuses to delete either alone. One statement removes both.
        Repo.query!(
          """
          WITH gone AS (
            DELETE FROM listing_addresses WHERE listing_id IN
              (SELECT id FROM listings WHERE user_id <> ALL($1))
          )
          DELETE FROM listings WHERE user_id <> ALL($1)
          """,
          [Enum.map(users_before, &Ecto.UUID.dump!/1)]
        )

        Repo.delete_all(from r in Region, where: r.id not in ^regions_before)
        Repo.delete_all(from u in User, where: u.id not in ^users_before)
      end)
    end)
  end

  test "REQ-003-12: two submissions at the same moment cannot exceed the limit" do
    {scope, drafts} =
      unboxed(fn ->
        scope = ListingsFixtures.employer_scope_fixture()
        region_id = Jairojobs.RegionsFixtures.region_fixture().id
        attrs = fn -> ListingsFixtures.complete_listing_attrs(region_id: region_id) end

        for _ <- 1..2 do
          {:ok, _} =
            Listings.submit_listing(
              scope,
              ListingsFixtures.listing_fixture(scope, attrs.()),
              &ListingsFixtures.admin_url/1
            )
        end

        {scope, for(_ <- 1..4, do: ListingsFixtures.listing_fixture(scope, attrs.()))}
      end)

    results =
      drafts
      |> Enum.map(fn draft ->
        Task.async(fn ->
          unboxed(fn -> Listings.submit_listing(scope, draft, &ListingsFixtures.admin_url/1) end)
        end)
      end)
      |> Task.await_many(15_000)

    assert Enum.count(results, &match?({:ok, %Listing{status: :pending}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :limit_reached})) == 3
    assert unboxed(fn -> Listings.count_open_listings(scope) end) == 3
  end

  # spec 004, plan decision 11. An Employer withdraws at the instant an Admin approves.
  # Whichever comes second must see the other's result and be refused; the listing must
  # never end up a Draft that carries an approval, or Published after a withdrawal.
  test "an approval and a withdrawal at the same moment leave one consistent listing" do
    rounds = 40

    {owner, admin, listings} =
      unboxed(fn ->
        # An Admin owner has no limit on open listings, so one account can hold them all.
        owner = ListingsFixtures.admin_poster_scope_fixture()
        admin = Jairojobs.AccountsFixtures.admin_scope_fixture()
        region_id = Jairojobs.RegionsFixtures.region_fixture().id

        listings =
          for _ <- 1..rounds do
            ListingsFixtures.listing_in_status_fixture(owner, :pending, region_id: region_id)
          end

        {owner, admin, listings}
      end)

    url = &"https://jairojobs.test/my/listings/#{&1.id}"

    outcomes =
      for listing <- listings do
        approve =
          Task.async(fn -> unboxed(fn -> Listings.approve_listing(admin, listing, url) end) end)

        withdraw =
          Task.async(fn -> unboxed(fn -> Listings.withdraw_listing(owner, listing) end) end)

        {Task.await(approve, 15_000), Task.await(withdraw, 15_000),
         unboxed(fn -> Repo.get!(Listing, listing.id) end)}
      end

    for {approved, withdrawn, stored} <- outcomes do
      case {approved, withdrawn} do
        {{:ok, %Listing{status: :published}, _email}, {:error, :invalid_status}} ->
          assert %Listing{status: :published, published_at: %DateTime{}} = stored
          assert stored.decided_by_id == admin.user.id

        {{:error, :not_pending}, {:ok, %Listing{status: :draft}}} ->
          assert %Listing{status: :draft, published_at: nil, decided_at: nil} = stored
          assert stored.decided_by_id == nil

        {approved, withdrawn} ->
          flunk(
            "both went through, or neither did: approve #{outcome(approved)}, " <>
              "withdraw #{outcome(withdrawn)}, stored as #{stored.status} with " <>
              "published_at #{inspect(stored.published_at)}"
          )
      end
    end
  end

  # spec 005, plan decision 4. Two Admins approve two listings with the same title in
  # the same region at the same instant. Both read which addresses are taken; without
  # the lock on the region's row both would pick the same one, and the second would
  # crash on the unique index. They must take turns, and each get an address of its own.
  test "REQ-005-6: two approvals of the same title at the same moment get different addresses" do
    rounds = 25

    {admins, pairs} =
      unboxed(fn ->
        owner = ListingsFixtures.admin_poster_scope_fixture()
        admins = for _ <- 1..2, do: Jairojobs.AccountsFixtures.admin_scope_fixture()
        region_id = Jairojobs.RegionsFixtures.region_fixture().id

        pairs =
          for round <- 1..rounds do
            for _ <- 1..2 do
              ListingsFixtures.listing_in_status_fixture(owner, :pending,
                region_id: region_id,
                title: "Racing barista #{round}"
              )
            end
          end

        {admins, pairs}
      end)

    url = &"https://jairojobs.test/my/listings/#{&1.id}"

    for {pair, round} <- Enum.with_index(pairs, 1) do
      results =
        [pair, admins]
        |> Enum.zip()
        |> Enum.map(fn {listing, admin} ->
          Task.async(fn -> unboxed(fn -> Listings.approve_listing(admin, listing, url) end) end)
        end)
        |> Task.await_many(15_000)

      slugs =
        for {:ok, %Listing{status: :published, slug: slug}, _email} <- results, do: slug

      assert Enum.sort(slugs) == ["racing-barista-#{round}", "racing-barista-#{round}-2"],
             "round #{round}: #{inspect(results)}"
    end
  end

  defp outcome({:ok, %Listing{status: status}}), do: "ok (#{status})"
  defp outcome({:ok, %Listing{status: status}, _email}), do: "ok (#{status})"
  defp outcome({:error, reason}), do: "refused (#{inspect(reason)})"

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
