defmodule Jairojobs.ListingsConcurrencyTest do
  # Not async, and outside the usual sandbox (constitution §3.5): this test needs two real
  # database connections racing each other. Inside the sandbox both tasks would share one
  # transaction and the owner-row lock in `submit_listing/2` would prove nothing. Everything
  # it commits is deleted again in `on_exit`.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Jairojobs.Accounts.User
  alias Jairojobs.Listings
  alias Jairojobs.Listings.Listing
  alias Jairojobs.ListingsFixtures
  alias Jairojobs.Regions.Region
  alias Jairojobs.Repo

  test "REQ-003-12: two submissions at the same moment cannot exceed the limit" do
    users_before = unboxed(fn -> Repo.all(from u in User, select: u.id) end)
    regions_before = unboxed(fn -> Repo.all(from r in Region, select: r.id) end)

    on_exit(fn ->
      unboxed(fn ->
        new_users = from u in User, where: u.id not in ^users_before, select: u.id
        Repo.delete_all(from l in Listing, where: l.user_id in subquery(new_users))
        Repo.delete_all(from r in Region, where: r.id not in ^regions_before)
        Repo.delete_all(from u in User, where: u.id not in ^users_before)
      end)
    end)

    {scope, drafts} =
      unboxed(fn ->
        scope = ListingsFixtures.employer_scope_fixture()
        region_id = Jairojobs.RegionsFixtures.region_fixture().id
        attrs = fn -> ListingsFixtures.complete_listing_attrs(region_id: region_id) end

        for _ <- 1..2 do
          {:ok, _} =
            Listings.submit_listing(scope, ListingsFixtures.listing_fixture(scope, attrs.()))
        end

        {scope, for(_ <- 1..4, do: ListingsFixtures.listing_fixture(scope, attrs.()))}
      end)

    results =
      drafts
      |> Enum.map(fn draft ->
        Task.async(fn -> unboxed(fn -> Listings.submit_listing(scope, draft) end) end)
      end)
      |> Task.await_many(15_000)

    assert Enum.count(results, &match?({:ok, %Listing{status: :pending}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :limit_reached})) == 3
    assert unboxed(fn -> Listings.count_open_listings(scope) end) == 3
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
