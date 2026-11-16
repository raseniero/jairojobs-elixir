defmodule Jairojobs.Listings do
  @moduledoc """
  Listings as their owner sees and manages them (spec 003), and as Admins
  moderate them (spec 004).

  Every function that touches stored listings takes the current scope first.
  Only an Employer or Admin may post, and an account only ever reads or
  changes its own listings: someone else's listing is treated exactly like one
  that does not exist (REQ-003-14).

  The moderation functions are the exception: they act on anyone's listing,
  and only for an Admin. Each one checks the role itself, re-reads it from the
  database, and locks the listing row before it looks at the status
  (REQ-004-1).
  """

  import Ecto.Query, warn: false

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Accounts.User
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Repo

  # spec 003 — REQ-003-12: open (Pending + Published) listings a free Employer may have.
  @open_listing_limit 3
  @open_statuses [:pending, :published]

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
    scope
    |> with_my_listing(listing, fn listing ->
      with :ok <- editable(listing) do
        listing |> Listing.draft_changeset(attrs) |> Repo.update()
      end
    end)
    |> preload_region()
  end

  @doc """
  Deletes a Draft or Rejected listing for good (REQ-003-11). A listing that is
  or ever was Published is never deleted. Returns `{:ok, listing}` or the same
  errors as `update_listing/3` (without the changeset).
  """
  def delete_listing(scope, %Listing{} = listing) do
    with_my_listing(scope, listing, fn listing ->
      with :ok <- editable(listing), do: Repo.delete(listing)
    end)
  end

  @doc """
  The required parts a listing still lacks before it can be submitted; `[]`
  when it is complete (REQ-003-4). See `Listing.missing_fields/1`.
  """
  def missing_fields(%Listing{} = listing), do: Listing.missing_fields(listing)

  @doc """
  How many listings the scoped account has open — Pending or Published
  (REQ-003-12).
  """
  def count_open_listings(scope) do
    if Scope.poster?(scope), do: count_open(scope.user.id), else: 0
  end

  defp count_open(user_id) do
    Repo.aggregate(
      from(l in Listing, where: l.user_id == ^user_id and l.status in ^@open_statuses),
      :count
    )
  end

  @doc """
  The most listings the scoped account may have open at once: `3` for an
  Employer, `:unlimited` for an Admin (REQ-003-12).
  """
  def open_listing_limit(scope) do
    if Scope.admin?(scope), do: :unlimited, else: @open_listing_limit
  end

  @doc """
  Submits a Draft or Rejected listing for approval (REQ-003-6, REQ-003-8).
  The listing becomes Pending; only an Admin approval (spec 004) publishes it.
  Returns:

    * `{:ok, listing}`
    * `{:error, :invalid_status}` — not a Draft or Rejected listing
    * `{:error, {:incomplete, fields}}` — see `missing_fields/1`
    * `{:error, :region_hidden}` — its region is no longer offered
    * `{:error, :limit_reached}` — an Employer already has 3 open listings
    * `{:error, :not_found}` / `{:error, :unauthorized}`

  Runs in a transaction that locks the owner's account row, so two
  submissions at the same moment cannot both pass the limit check.
  """
  def submit_listing(scope, %Listing{} = listing) do
    if Scope.poster?(scope) do
      Repo.transaction(fn ->
        owner = Repo.one!(from u in User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")

        with {:ok, listing} <- lock_mine(scope, listing),
             :ok <- submittable(listing),
             :ok <- complete(listing),
             :ok <- region_active(listing),
             :ok <- within_limit(owner),
             {:ok, listing} <-
               listing |> Listing.submit_changeset(owner, DateTime.utc_now()) |> Repo.update() do
          Repo.preload(listing, :region, force: true)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Takes a Pending listing back to Draft so it can be edited again
  (REQ-003-7). It leaves the approval queue and frees a place under the limit.

  Returns `{:ok, listing}`, `{:error, :invalid_status}` for any other status,
  or `{:error, :not_found}` / `{:error, :unauthorized}`.
  """
  def withdraw_listing(scope, %Listing{} = listing) do
    transition(scope, listing, :pending, status: :draft, submitted_at: nil)
  end

  @doc """
  Closes a Published listing (REQ-003-9). Closed is final: the listing is no
  longer public, stays in My listings and frees a place under the limit.

  Returns the same shapes as `withdraw_listing/2`.
  """
  def close_listing(scope, %Listing{} = listing) do
    transition(scope, listing, :published, status: :closed, closed_at: DateTime.utc_now())
  end

  ## Moderation (spec 004)

  @moderation_statuses [:pending, :published, :rejected, :taken_down, :closed]
  @moderation_page_size 50

  @doc """
  How many listings are waiting for approval (REQ-004-2). `0` for anyone who
  is not an Admin.
  """
  def count_pending_listings(scope) do
    if Scope.admin?(scope) do
      Repo.aggregate(from(l in Listing, where: l.status == :pending), :count)
    else
      0
    end
  end

  @doc """
  One page of everyone's listings in `status`, for an Admin (REQ-004-2,
  REQ-004-3), with their region preloaded.

  `:pending` is the approval queue: longest-waiting first, counted from the
  latest submission. Every other status is most recently changed first.
  Drafts belong to their Employer alone and cannot be asked for.

  Options: `:offset` (default `0`) and `:limit` (default `50`). Returns
  `{listings, more?}`, where `more?` says whether listings remain after this
  page. `{[], false}` for anyone who is not an Admin.
  """
  def list_listings_for_moderation(scope, status, opts \\ []) do
    if Scope.admin?(scope) and status in @moderation_statuses do
      limit = Keyword.get(opts, :limit, @moderation_page_size)
      offset = Keyword.get(opts, :offset, 0)

      listings =
        Repo.all(
          from l in Listing,
            where: l.status == ^status,
            order_by: ^moderation_order(status),
            offset: ^offset,
            limit: ^(limit + 1),
            preload: [:region]
        )

      {Enum.take(listings, limit), length(listings) > limit}
    else
      {[], false}
    end
  end

  defp moderation_order(:pending), do: [asc: :submitted_at, asc: :id]
  defp moderation_order(_status), do: [desc: :updated_at, desc: :id]

  @doc """
  Gets any submitted listing for an Admin, with its region, its owner and the
  Admin who made the latest decision preloaded (REQ-004-4).

  Raises `Ecto.NoResultsError` when the id is unknown or malformed, when the
  listing is a Draft (one its Employer withdrew included), or when the scope is not
  an Admin — all look the same to the caller.
  """
  def get_listing_for_moderation!(scope, id) do
    with true <- Scope.admin?(scope),
         {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.one!(
        from l in Listing,
          where: l.id == ^id and l.status in ^@moderation_statuses,
          preload: [:region, :user, :decided_by]
      )
    else
      _ -> raise Ecto.NoResultsError, queryable: Listing
    end
  end

  @doc """
  A changeset for the reason on the reject and take-down forms: `reason`,
  trimmed, 10–500 characters (REQ-004-6, REQ-004-7).
  """
  def change_reason(attrs \\ %{}), do: Listing.reason_changeset(attrs)

  @doc """
  Approves a Pending listing: it becomes Published, and the time and the Admin
  are recorded (REQ-004-5). Nothing the Employer wrote is changed. Any Admin
  may approve any waiting listing, their own included.

  `owner_url` turns the listing into the address of its page in My listings,
  for the email to its owner (REQ-004-9). Returns:

    * `{:ok, listing, email}` — `email` says what happened to that email
    * `{:error, :not_pending}` — no longer waiting: withdrawn, or already decided
    * `{:error, :region_hidden}` — its region is hidden; nothing changes
    * `{:error, :not_found}` — the listing no longer exists
    * `{:error, :unauthorized}` — the scope is not an Admin
  """
  def approve_listing(scope, %Listing{} = listing, owner_url) when is_function(owner_url, 1) do
    scope
    |> moderate(listing, fn admin, listing ->
      with :ok <- in_status(listing, [:pending], :not_pending),
           :ok <- region_active(listing) do
        listing |> Listing.approve_changeset(admin, DateTime.utc_now()) |> Repo.update()
      end
    end)
    |> notify_owner(owner_url)
  end

  @doc """
  Rejects a Pending listing with a reason its Employer will read (REQ-004-6).
  It becomes Rejected and stops counting toward the Employer's limit.

  `attrs` holds `reason`, as `change_reason/1` describes. Returns the same
  shapes as `approve_listing/3`, without `:region_hidden`, plus
  `{:error, changeset}` when the reason is missing, too short or too long.
  """
  def reject_listing(scope, %Listing{} = listing, attrs, owner_url)
      when is_function(owner_url, 1) do
    scope
    |> moderate(listing, fn admin, listing ->
      with :ok <- in_status(listing, [:pending], :not_pending),
           {:ok, reason} <- reason(attrs) do
        listing |> Listing.reject_changeset(admin, reason, DateTime.utc_now()) |> Repo.update()
      end
    end)
    |> notify_owner(owner_url)
  end

  @doc """
  Takes a Published listing down with a reason its Employer will read
  (REQ-004-7). Taken down is final for everyone; the listing is kept.

  Returns `{:ok, listing, email}`, `{:error, changeset}` for a bad reason,
  `{:error, :not_published}` when the listing is no longer live, or
  `{:error, :not_found}` / `{:error, :unauthorized}`.
  """
  def take_down_listing(scope, %Listing{} = listing, attrs, owner_url)
      when is_function(owner_url, 1) do
    scope
    |> moderate(listing, fn admin, listing ->
      with :ok <- in_status(listing, [:published], :not_published),
           {:ok, reason} <- reason(attrs) do
        listing |> Listing.take_down_changeset(admin, reason, DateTime.utc_now()) |> Repo.update()
      end
    end)
    |> notify_owner(owner_url)
  end

  # Runs one Admin action in a transaction. The role is re-read from the
  # database (the scope may be stale) and the listing row is locked and read
  # fresh, so the status the action checks is the status it changes.
  defp moderate(scope, %Listing{id: id}, action) do
    if Scope.admin?(scope) do
      Repo.transaction(fn ->
        with {:ok, admin} <- fetch_admin(scope),
             {:ok, listing} <- lock_listing(id),
             {:ok, listing} <- action.(admin, listing) do
          Repo.preload(listing, :region, force: true)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  defp fetch_admin(scope) do
    case Repo.get(User, scope.user.id) do
      %User{role: :admin} = admin -> {:ok, admin}
      _demoted_or_gone -> {:error, :unauthorized}
    end
  end

  # A Draft is locked and returned like any other row: an action on a listing
  # its Employer has just withdrawn is refused for its status, not as "not found".
  defp lock_listing(id) do
    case Repo.one(from l in Listing, where: l.id == ^id, lock: "FOR UPDATE") do
      %Listing{} = listing -> {:ok, listing}
      nil -> {:error, :not_found}
    end
  end

  defp in_status(%Listing{status: status}, allowed, refusal) do
    if status in allowed, do: :ok, else: {:error, refusal}
  end

  defp reason(attrs) do
    with {:ok, %{reason: reason}} <-
           attrs |> Listing.reason_changeset() |> Ecto.Changeset.apply_action(:insert) do
      {:ok, reason}
    end
  end

  # The email to the listing's owner is added with the notifier (REQ-004-9).
  # Until then nothing is sent, which is what `:own_listing` reports.
  defp notify_owner({:ok, listing}, _owner_url), do: {:ok, listing, :own_listing}
  defp notify_owner({:error, reason}, _owner_url), do: {:error, reason}

  defp transition(scope, listing, from, changes) do
    scope
    |> with_my_listing(listing, fn listing ->
      if listing.status == from do
        listing |> Ecto.Changeset.change(changes) |> Repo.update()
      else
        {:error, :invalid_status}
      end
    end)
    |> preload_region()
  end

  defp submittable(%Listing{status: status}) when status in [:draft, :rejected], do: :ok
  defp submittable(%Listing{}), do: {:error, :invalid_status}

  defp complete(listing) do
    case Listing.missing_fields(listing) do
      [] -> :ok
      fields -> {:error, {:incomplete, fields}}
    end
  end

  defp region_active(listing) do
    case Repo.preload(listing, :region).region do
      %{active: true} -> :ok
      _hidden -> {:error, :region_hidden}
    end
  end

  # The role is read from the locked row, not from the (possibly stale) scope.
  defp within_limit(%User{role: :admin}), do: :ok

  defp within_limit(%User{id: id}) do
    if count_open(id) < @open_listing_limit, do: :ok, else: {:error, :limit_reached}
  end

  # Runs one owner action on the scoped account's own listing, in a transaction
  # that holds the listing's row lock. An Admin may be deciding the same listing
  # at the same moment (spec 004): whoever comes second waits, then sees the
  # status the first one left and is refused.
  defp with_my_listing(scope, %Listing{} = listing, action) do
    Repo.transaction(fn ->
      with {:ok, listing} <- lock_mine(scope, listing),
           {:ok, result} <- action.(listing) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The stored row, locked, never the struct we were handed: the caller's copy
  # may be stale or may belong to someone else (constitution §2.7). Must be
  # called inside a transaction.
  defp lock_mine(scope, %Listing{id: id}) do
    cond do
      not Scope.poster?(scope) ->
        {:error, :unauthorized}

      listing =
          Repo.one(
            from l in Listing,
              where: l.id == ^id and l.user_id == ^scope.user.id,
              lock: "FOR UPDATE"
          ) ->
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
