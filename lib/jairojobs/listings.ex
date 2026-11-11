defmodule Jairojobs.Listings do
  @moduledoc """
  Listings as their owner sees and manages them (spec 003).

  Every function that touches stored listings takes the current scope first.
  Only an Employer or Admin may post, and an account only ever reads or
  changes its own listings: someone else's listing is treated exactly like one
  that does not exist (REQ-003-14). Admin moderation is spec 004.
  """

  import Ecto.Query, warn: false

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Repo

  @doc """
  The scoped account's listings, most recently changed first, with their
  region preloaded (REQ-003-13). Empty for a scope that may not post.
  """
  def list_my_listings(scope) do
    if Scope.poster?(scope) do
      Repo.all(
        from l in Listing,
          where: l.user_id == ^scope.user.id,
          order_by: [desc: l.updated_at, desc: l.id],
          preload: [:region]
      )
    else
      []
    end
  end

  @doc """
  Gets one of the scoped account's listings, region preloaded.

  Raises `Ecto.NoResultsError` when the id is unknown, malformed, or belongs
  to another account — all three look the same to the caller (REQ-003-14).
  """
  def get_my_listing!(scope, id) do
    with true <- Scope.poster?(scope),
         {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one!(
        from l in Listing,
          where: l.id == ^id and l.user_id == ^scope.user.id,
          preload: [:region]
      )
    else
      _ -> raise Ecto.NoResultsError, queryable: Listing
    end
  end

  @doc """
  A changeset for the listing form.
  """
  def change_listing(%Listing{} = listing, attrs \\ %{}) do
    Listing.draft_changeset(listing, attrs)
  end

  @doc """
  Saves a new Draft owned by the scoped account (REQ-003-3). Only a title is
  required. Returns:

    * `{:ok, listing}`
    * `{:error, changeset}` — no title, or a filled-in field is invalid
    * `{:error, :unauthorized}` — the scope is not an Employer or Admin
    * `{:error, :business_details_required}` — no business details saved yet (REQ-003-2)
  """
  def create_listing(scope, attrs) do
    cond do
      not Scope.poster?(scope) ->
        {:error, :unauthorized}

      not Accounts.business_details?(scope.user) ->
        {:error, :business_details_required}

      true ->
        %Listing{user_id: scope.user.id}
        |> Listing.draft_changeset(attrs)
        |> Repo.insert()
        |> preload_region()
    end
  end

  @doc """
  Changes a Draft or Rejected listing; the status stays as it is (REQ-003-5).
  Returns:

    * `{:ok, listing}`
    * `{:error, changeset}` — same field rules as a new draft
    * `{:error, :locked}` — the listing is Pending, Published, Closed or Taken down
    * `{:error, :not_found}` — not the scoped account's listing
    * `{:error, :unauthorized}` — the scope is not an Employer or Admin
  """
  def update_listing(scope, %Listing{} = listing, attrs) do
    with {:ok, listing} <- fetch_mine(scope, listing),
         :ok <- editable(listing) do
      listing
      |> Listing.draft_changeset(attrs)
      |> Repo.update()
      |> preload_region()
    end
  end

  @doc """
  Deletes a Draft or Rejected listing for good (REQ-003-11). A listing that is
  or ever was Published is never deleted. Returns `{:ok, listing}` or the same
  errors as `update_listing/3` (without the changeset).
  """
  def delete_listing(scope, %Listing{} = listing) do
    with {:ok, listing} <- fetch_mine(scope, listing),
         :ok <- editable(listing) do
      Repo.delete(listing)
    end
  end

  # The stored row, never the struct we were handed: the caller's copy may be
  # stale or may belong to someone else (constitution §2.7).
  defp fetch_mine(scope, %Listing{id: id}) do
    cond do
      not Scope.poster?(scope) ->
        {:error, :unauthorized}

      listing = Repo.get_by(Listing, id: id, user_id: scope.user.id) ->
        {:ok, listing}

      true ->
        {:error, :not_found}
    end
  end

  defp editable(%Listing{status: status}) when status in [:draft, :rejected], do: :ok
  defp editable(%Listing{}), do: {:error, :locked}

  defp preload_region({:ok, listing}), do: {:ok, Repo.preload(listing, :region, force: true)}
  defp preload_region(other), do: other
end
