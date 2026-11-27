defmodule PhoneCheck do
  @moduledoc """
  Shared by the pages files in this folder (`NNN.exs`), which
  `scripts/phone-check.sh NNN` runs against the dev database to check a spec's
  screens at phone width.

  Everything created here is throwaway and named so that `cleanup/0` finds all
  of it: accounts are `phonecheck-…@example.com`, regions "Phonecheck …".
  Never give real data such a name.
  """
  import Ecto.Query

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.{Scope, User, UserToken}
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Listings.ListingAddress
  alias Jairojobs.Regions
  alias Jairojobs.Regions.Region
  alias Jairojobs.Repo

  @doc """
  Runs the command the runner asked for: `setup` (prints the pages the given
  function returns), `cleanup` or `counts`.
  """
  def run(["setup"], setup), do: emit("JSON", Jason.encode!(setup.()))
  def run(["cleanup"], _setup), do: emit("CLEANUP", cleanup())
  def run(["counts"], _setup), do: emit("COUNTS", counts())

  def run(_other, _setup),
    do: IO.puts("usage: mix run priv/phone_check/NNN.exs setup|cleanup|counts")

  defp emit(marker, text), do: IO.puts("PHONECHECK_#{marker}:#{text}")

  def unique, do: System.unique_integer([:positive])

  @doc "A confirmed account with `role`, as its scope."
  def account(role) do
    {:ok, user} =
      Accounts.register_user(%{email: "phonecheck-#{unique()}@example.com", role: role})

    user
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now())
    |> Repo.update!()
    |> Scope.for_user()
  end

  @doc "A confirmed Admin, as its scope."
  def admin do
    {:ok, user} = Accounts.promote_to_admin(Scope.system(), account("candidate").user)
    Scope.for_user(user)
  end

  @doc "Saves business details for `scope`'s account and returns the new scope."
  def business(scope, attrs) do
    {:ok, user} = Accounts.update_business_details(scope, attrs)
    Scope.for_user(user)
  end

  @doc "A region whose name marks it as throwaway."
  def region(admin, name) do
    {:ok, region} = Regions.create_region(admin, %{name: "Phonecheck #{name} #{unique()}"})
    region
  end

  @doc "The path of a one-time log-in link for `scope`'s account."
  def login(%Scope{user: user}) do
    {token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    "/users/log-in/#{token}"
  end

  @doc "Removes everything these scripts created, whichever spec made it."
  def cleanup do
    users = from u in User, where: like(u.email, "phonecheck-%@example.com"), select: u.id
    mine = from l in Listing, where: l.user_id in subquery(users), select: l.id

    # A listing's public addresses go first: the database refuses to delete a listing
    # that has one (spec 005).
    Repo.delete_all(from a in ListingAddress, where: a.listing_id in subquery(mine))
    {listings, _} = Repo.delete_all(from l in Listing, where: l.user_id in subquery(users))
    {regions, _} = Repo.delete_all(from r in Region, where: like(r.name, "Phonecheck %"))
    {users, _} = Repo.delete_all(from u in User, where: like(u.email, "phonecheck-%@example.com"))
    "removed #{listings} listings, #{regions} regions, #{users} users"
  end

  @doc "Listings, users and regions in the database, for the before-and-after check."
  def counts do
    Enum.map_join([Listing, User, Region], ",", &Repo.aggregate(&1, :count))
  end
end
