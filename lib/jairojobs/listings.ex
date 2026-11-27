defmodule Jairojobs.Listings do
  @moduledoc """
  Listings as their owner sees and manages them (spec 003), as Admins
  moderate them (spec 004), and as the public reads them (spec 005).

  Every function that touches stored listings takes the current scope first.
  Only an Employer or Admin may post, and an account only ever reads or
  changes its own listings: someone else's listing is treated exactly like one
  that does not exist (REQ-003-14).

  The moderation functions are the exception: they act on anyone's listing,
  and only for an Admin. Each one checks the role itself, re-reads it from the
  database, and locks the listing row before it looks at the status
  (REQ-004-1).

  The public reads take no scope at all: they return Published listings and
  nothing else, the same for everyone (REQ-005-1).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Accounts.User
  alias Jairojobs.Listings.Listing
  alias Jairojobs.Listings.ListingAddress
  alias Jairojobs.Listings.ListingNotifier
  alias Jairojobs.Listings.Slug
  alias Jairojobs.Regions.Region
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

  Once the submission has committed, every Admin except the submitter is
  emailed that a listing is waiting (REQ-004-10). `admin_url` turns the
  listing into the address of its Admin view for that email. The submission
  never fails because of the email: the listing is in the queue either way.
  """
  def submit_listing(scope, %Listing{} = listing, admin_url) when is_function(admin_url, 1) do
    scope |> submit(listing) |> notify_admins(scope, admin_url)
  end

  defp submit(scope, listing) do
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

  ## The public side (spec 005)

  @public_page_size 20

  # The one way to ask for public listings (REQ-005-1): only the status decides.
  # Every public read is built on this query and on nothing else, so a listing
  # that is not Published cannot reach a public page whatever a screen asks for.
  # Not the region (a hidden one hides nothing), not the owner's role, and not
  # who is looking: these functions take no scope because the answer is the
  # same for everyone.
  defp published, do: from(l in Listing, where: l.status == :published)

  @doc """
  One page of the Published listings, newest approval first, with their
  region preloaded (REQ-005-1, REQ-005-2). Nothing else is ever returned:
  no Draft, Pending, Rejected, Closed or Taken down listing.

  Options:

    * `:region` — a `Region`: only its listings (REQ-005-3). A hidden region's
      listings are returned like any other's
    * `:search` — words to look for (REQ-005-4), cleaned by `search_words/1`.
      A listing matches when every word is found, as a whole word and whatever
      its capitals, in its title, business name, area, "About the job",
      Requirements or Benefits. Nothing typed is no search
    * `:type` — an employment type such as `:part_time`; `nil` is any type
    * `:limit` (default `20`) and `:offset` (default `0`)

  Returns `{listings, total}`. `total` counts every listing that matched, not
  only this page.

  A search narrows the list and never reorders it: there is no ordering by how
  well a listing matches. What was searched is not stored.

  The order never changes: an Admin's edit does not move a listing, because it
  does not touch the time of approval.
  """
  def list_public_listings(opts \\ []) do
    query = Enum.reduce(opts, published(), &narrow/2)

    # Searched words are never written to a log (spec 005, privacy). At its most
    # detailed level Ecto logs every query with the values given to it, and the words
    # are such a value, so the two queries of a search are not logged at all.
    quietly = if search_words(opts[:search]), do: [log: false], else: []

    listings =
      Repo.all(
        from(l in query,
          order_by: [desc: l.published_at, desc: l.id],
          limit: ^Keyword.get(opts, :limit, @public_page_size),
          offset: ^Keyword.get(opts, :offset, 0),
          preload: [:region]
        ),
        quietly
      )

    {listings, Repo.aggregate(query, :count, quietly)}
  end

  @max_search_length 100

  @doc """
  The words of a search as they are used and shown: trimmed, and cut at 100
  characters (REQ-005-4). `nil` when nothing was typed, or only spaces, which
  is no search at all.

  The screens use this too, so the words in the search field and in the
  page's address are exactly the words that were looked for.
  """
  def search_words(words) when is_binary(words) do
    words
    # A control character is never part of a word, and the database refuses a null byte.
    |> String.replace(~r/[\x00-\x1F\x7F]/u, " ")
    |> String.trim()
    |> String.slice(0, @max_search_length)
    |> String.trim()
    |> case do
      "" -> nil
      words -> words
    end
  end

  def search_words(_not_text), do: nil

  defp narrow({:region, %Region{id: region_id}}, query),
    do: from(l in query, where: l.region_id == ^region_id)

  defp narrow({:region, nil}, query), do: query

  # Postgres full-text search with the `simple` configuration (plan decision 7):
  # whole words, every word, capitals ignored, and no guessing at word endings
  # or leaving "small" words out. `plainto_tsquery` reads the words as plain
  # text, so nothing typed can act as an operator, a wildcard or a quote.
  defp narrow({:search, words}, query) do
    case search_words(words) do
      nil ->
        query

      words ->
        from l in query,
          where:
            fragment(
              "to_tsvector('simple', concat_ws(' ', ?, ?, ?, ?, ?, ?)) @@ plainto_tsquery('simple', ?)",
              l.title,
              l.business_name,
              l.area,
              l.description,
              l.requirements,
              l.benefits,
              ^words
            )
    end
  end

  defp narrow({:type, nil}, query), do: query
  defp narrow({:type, type}, query), do: from(l in query, where: l.employment_type == ^type)
  defp narrow({option, _value}, query) when option in [:limit, :offset], do: query

  @doc """
  What the public address `/jobs/<region_slug>/<listing_slug>` is (REQ-005-6,
  REQ-005-7):

    * `{:ok, listing}` — the current address of a Published listing, which
      comes with its region preloaded
    * `{:moved, %{region_slug: …, slug: …}}` — an address the listing had
      before an Admin moved it to another region; the map is its current
      address. This is answered whatever the listing's status is now: an
      earlier address forwards first, and the current one says the rest
    * `{:gone, %{id: …, user_id: …, region: …}}` — the current address of a
      listing that was Published and is now Closed or Taken down. Nothing of
      the listing itself is returned: only its region, for the way onward, and
      whose it is, so its owner and Admins can be given their link
    * `:not_found` — no listing ever had this address. A Draft, a Pending and
      a Rejected listing have none, and a listing's id is never one

  Takes no scope: the answer is the same for everyone.
  """
  def resolve_public_address(region_slug, listing_slug) do
    with true <- Region.slug?(region_slug) and Region.slug?(listing_slug),
         %{} = address <- address_at(region_slug, listing_slug) do
      answer(address)
    else
      _never_an_address -> :not_found
    end
  end

  # The recorded address, with the little of its listing that says what the
  # address is now. Not the listing itself: only a Published one is ever read,
  # and only through `published/0`.
  defp address_at(region_slug, listing_slug) do
    Repo.one(
      from a in ListingAddress,
        join: r in assoc(a, :region),
        join: l in assoc(a, :listing),
        join: current in assoc(l, :region),
        where: r.slug == ^region_slug and a.slug == ^listing_slug,
        select: %{
          listing_id: l.id,
          user_id: l.user_id,
          current?: a.region_id == l.region_id,
          current: %{region_slug: current.slug, slug: l.slug},
          region: current
        }
    )
  end

  defp answer(%{current?: false, current: current}), do: {:moved, current}

  defp answer(%{listing_id: id, user_id: user_id, region: region}) do
    case Repo.one(from l in published(), where: l.id == ^id, preload: [:region]) do
      %Listing{} = listing -> {:ok, listing}
      nil -> {:gone, %{id: id, user_id: user_id, region: region}}
    end
  end

  @doc """
  The public address of every Published listing, newest approval first, for
  the sitemap (REQ-005-9): `%{region_slug: …, slug: …, updated_at: …}`. A
  listing in a hidden region is included; nothing that is not Published is.
  """
  def list_public_addresses do
    Repo.all(
      from l in published(),
        join: r in assoc(l, :region),
        order_by: [desc: l.published_at, desc: l.id],
        select: %{region_slug: r.slug, slug: l.slug, updated_at: l.updated_at}
    )
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

  Approval also gives the listing its public address (REQ-005-6): a slug made
  from the title as it is now, unique within its region, numbered if another
  listing has or ever had the same one. The slug is on the listing returned.

  `owner_url` turns the listing into the address of its page in My listings,
  and `public_url` into the full address of its public page, for the email to
  its owner (REQ-004-9, REQ-005-10). Both are functions of the listing: a
  context cannot build web addresses, and the public one does not exist until
  the approval has made it. Returns:

    * `{:ok, listing, email}` — `email` says what happened to that email
    * `{:error, :not_pending}` — no longer waiting: withdrawn, or already decided
    * `{:error, :region_hidden}` — its region is hidden; nothing changes
    * `{:error, :not_found}` — the listing no longer exists
    * `{:error, :unauthorized}` — the scope is not an Admin
  """
  def approve_listing(scope, %Listing{} = listing, owner_url, public_url)
      when is_function(owner_url, 1) and is_function(public_url, 1) do
    scope
    |> moderate(listing, fn admin, listing ->
      with :ok <- in_status(listing, [:pending], :not_pending),
           {:ok, region} <- lock_active_region(listing.region_id) do
        slug = take_address(listing, region, Slug.from_title(listing.title))
        listing |> Listing.approve_changeset(admin, slug, DateTime.utc_now()) |> decide()
      end
    end)
    |> notify_owner(scope, %{owner: owner_url, public: public_url})
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
        listing |> Listing.reject_changeset(admin, reason, DateTime.utc_now()) |> decide()
      end
    end)
    |> notify_owner(scope, owner_url)
  end

  @doc """
  Takes a Published listing down with a reason its Employer will read
  (REQ-004-7). Taken down is final for everyone; the listing is kept.

  Returns `{:ok, listing, email}`, `{:error, changeset}` for a bad reason,
  `{:error, :not_published}` when the listing is no longer published, or
  `{:error, :not_found}` / `{:error, :unauthorized}`.
  """
  def take_down_listing(scope, %Listing{} = listing, attrs, owner_url)
      when is_function(owner_url, 1) do
    scope
    |> moderate(listing, fn admin, listing ->
      with :ok <- in_status(listing, [:published], :not_published),
           {:ok, reason} <- reason(attrs) do
        listing |> Listing.take_down_changeset(admin, reason, DateTime.utc_now()) |> decide()
      end
    end)
    |> notify_owner(scope, owner_url)
  end

  @doc """
  A changeset for the Admin edit form (REQ-004-8).
  """
  def change_listing_as_admin(%Listing{} = listing, attrs \\ %{}) do
    Listing.admin_changeset(listing, attrs)
  end

  @doc """
  Saves an Admin's fix to a Pending or Published listing (REQ-004-8). The
  status, the place in the queue and the record of any decision stay as they
  are, and the account's own business details are never touched. No second
  approval is needed: the Admin who saves is the approver.

  The listing must stay complete. Its region may stay as it is, hidden or not,
  or move to an active region. When two Admins save the same listing, the
  later save replaces the earlier one.

  Moving a Published listing to another region moves its public address with
  it (REQ-005-6): the same slug there, or the next free number, or the address
  it had there if it was in that region before. Its earlier addresses stay
  recorded as its own, so they can forward. Nothing else in an edit touches
  the address, and the address cannot be set through `attrs`.

  Returns:

    * `{:ok, listing, email}` — saved; `email` as for `approve_listing/3`
    * `{:ok, listing, :unchanged}` — nothing differed; nothing saved, no email
    * `{:error, changeset}` — a field is missing or invalid; nothing saved
    * `{:error, :not_editable}` — no longer Pending or Published
    * `{:error, :not_found}` / `{:error, :unauthorized}`
  """
  def update_listing_as_admin(scope, %Listing{} = listing, attrs, owner_url)
      when is_function(owner_url, 1) do
    scope
    |> moderate(listing, fn _admin, listing ->
      with :ok <- in_status(listing, [:pending, :published], :not_editable) do
        listing
        |> Listing.admin_changeset(attrs)
        |> region_offered()
        |> move_address(listing)
        |> save_edit(listing)
      end
    end)
    |> notify_owner(scope, owner_url)
  end

  # The region's row, locked, if the region is active. Whoever is about to give
  # out an address in a region holds this lock until they commit, so two
  # approvals in one region take turns and never pick the same slug
  # (spec 005, plan decision 4). The lock also means an Admin cannot hide the
  # region between this check and the write.
  #
  # `FOR NO KEY UPDATE`, not `FOR UPDATE`: it holds off other address-givers and
  # a hide or a rename, but not an Employer saving a listing in the region, whose
  # foreign-key check only needs the region's key to stay put.
  defp lock_active_region(region_id) do
    case Repo.one(from r in Region, where: r.id == ^region_id, lock: "FOR NO KEY UPDATE") do
      %Region{active: true} = region -> {:ok, region}
      _hidden -> {:error, :region_hidden}
    end
  end

  # Records an address for `listing` in `region` and answers its slug: `wanted`,
  # or `wanted` with the next free number when a listing has or ever had that
  # address there (REQ-005-6). Must be called inside a transaction that holds
  # the region's row lock.
  defp take_address(%Listing{id: listing_id}, %Region{id: region_id}, wanted) do
    taken = Repo.all(from a in ListingAddress, where: a.region_id == ^region_id, select: a.slug)
    slug = Slug.free(wanted, taken)

    Repo.insert!(%ListingAddress{listing_id: listing_id, region_id: region_id, slug: slug})
    slug
  end

  # A changed region must be one that is offered: an active one. Keeping the
  # listing's own region is not a change, so a hidden one may stay.
  defp region_offered(changeset) do
    with {:ok, region_id} when not is_nil(region_id) <-
           Ecto.Changeset.fetch_change(changeset, :region_id),
         false <- match?(%Region{active: true}, Repo.get(Region, region_id)) do
      Ecto.Changeset.add_error(changeset, :region_id, "is not available")
    else
      _unchanged_or_active -> changeset
    end
  end

  # A Published listing whose region changes takes its public address along
  # (REQ-005-6). Only a valid edit gets this far, so no address is recorded for
  # a save that is then refused; and if the write itself fails, the transaction
  # rolls the address back with it.
  defp move_address(
         %Ecto.Changeset{valid?: true} = changeset,
         %Listing{status: :published} = listing
       ) do
    with {:ok, region_id} <- Ecto.Changeset.fetch_change(changeset, :region_id),
         {:ok, region} <- lock_active_region(region_id) do
      Listing.move_changeset(changeset, address_in(listing, region))
    else
      :error ->
        changeset

      {:error, :region_hidden} ->
        Ecto.Changeset.add_error(changeset, :region_id, "is not available")
    end
  end

  defp move_address(changeset, _pending_or_invalid), do: changeset

  # The slug of `listing`'s address in `region`: the one it had there if it was
  # in that region before, otherwise a new one, made from the slug it has now.
  defp address_in(%Listing{} = listing, %Region{} = region) do
    earlier =
      Repo.one(
        from a in ListingAddress,
          where: a.listing_id == ^listing.id and a.region_id == ^region.id,
          select: a.slug
      )

    earlier || take_address(listing, region, listing.slug)
  end

  defp save_edit(%Ecto.Changeset{valid?: true, changes: changes}, listing)
       when map_size(changes) == 0,
       do: {:ok, listing, :unchanged}

  defp save_edit(changeset, _listing) do
    with {:ok, listing} <- Repo.update(changeset) do
      # The slug is not a part of the listing the Employer wrote; the email names
      # the region that changed, which is why the address did.
      {:ok, listing, {:edited, Map.keys(changeset.changes) -- [:slug]}}
    end
  end

  defp decide(changeset) do
    with {:ok, listing} <- Repo.update(changeset), do: {:ok, listing, :decided}
  end

  # Runs one Admin action in a transaction. The role is re-read from the
  # database (the scope may be stale) and the listing row is locked and read
  # fresh, so the status the action checks is the status it changes.
  #
  # The action answers `{:ok, listing, what_happened}`; that pair comes back
  # as `{:ok, {listing, what_happened}}` once the transaction has committed.
  defp moderate(scope, %Listing{id: id}, action) do
    if Scope.admin?(scope) do
      Repo.transaction(fn ->
        with {:ok, admin} <- fetch_admin(scope),
             {:ok, listing} <- lock_listing(id),
             {:ok, listing, what_happened} <- action.(admin, listing) do
          {Repo.preload(listing, :region, force: true), what_happened}
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

  # Tells the Admins a listing is waiting (REQ-004-10), once the submission has
  # committed. Nobody is emailed about their own action, so an Admin who submits
  # is left out. A failed email is logged and otherwise ignored: the Employer is
  # never shown it, and the queue and its count do not depend on it.
  defp notify_admins({:error, reason}, _scope, _admin_url), do: {:error, reason}

  defp notify_admins({:ok, listing}, scope, admin_url) do
    admins = Repo.all(from u in User, where: u.role == :admin and u.id != ^scope.user.id)

    for admin <- admins do
      attempt(:submitted, listing, fn ->
        ListingNotifier.deliver_submitted(admin, listing, admin_url.(listing))
      end)
    end

    {:ok, listing}
  end

  # Emails the listing's owner what an Admin did (REQ-004-9), once the action
  # has committed: the decision is saved first and is never undone because of
  # the email. Nobody is emailed about their own action.
  #
  # The third element says what happened to the email: `:sent`, `:own_listing`
  # (the Admin owns the listing, nothing sent) or `:failed`.
  defp notify_owner({:error, reason}, _scope, _owner_url), do: {:error, reason}

  defp notify_owner({:ok, {listing, :unchanged}}, _scope, _owner_url),
    do: {:ok, listing, :unchanged}

  defp notify_owner({:ok, {%Listing{user_id: owner_id} = listing, _what}}, scope, _owner_url)
       when owner_id == scope.user.id,
       do: {:ok, listing, :own_listing}

  defp notify_owner({:ok, {listing, what_happened}}, _scope, urls) do
    kind = email_kind(listing, what_happened)

    {:ok, listing,
     attempt(kind, listing, fn ->
       # The owner, whatever their role is now (REQ-004-9).
       owner = Repo.get!(User, listing.user_id)
       deliver_to_owner(kind, owner, listing, what_happened, urls)
     end)}
  end

  defp email_kind(_listing, {:edited, _fields}), do: :edited
  defp email_kind(%Listing{status: :published}, :decided), do: :approved
  defp email_kind(%Listing{status: :rejected}, :decided), do: :rejected
  defp email_kind(%Listing{status: :taken_down}, :decided), do: :taken_down

  # Only the approval email carries two links: the listing's public page, and the
  # listing in My listings (REQ-005-10). The other three have the one.
  defp deliver_to_owner(:approved, owner, listing, _what, %{owner: owner_url, public: public_url}),
       do:
         ListingNotifier.deliver_approved(
           owner,
           listing,
           public_url.(listing),
           owner_url.(listing)
         )

  defp deliver_to_owner(kind, owner, listing, what, owner_url) when is_function(owner_url, 1),
    do: deliver_to_owner(kind, owner, listing, what, owner_url.(listing))

  defp deliver_to_owner(:rejected, owner, listing, _what, url),
    do: ListingNotifier.deliver_rejected(owner, listing, url)

  defp deliver_to_owner(:taken_down, owner, listing, _what, url),
    do: ListingNotifier.deliver_taken_down(owner, listing, url)

  defp deliver_to_owner(:edited, owner, listing, {:edited, fields}, url),
    do: ListingNotifier.deliver_edited(owner, listing, fields, url)

  # Sends one email and answers `:sent` or `:failed`. A refusal by the mail
  # service and an exception inside the adapter are treated alike: caught, and
  # logged with the listing's id and the kind of email — never an address, a
  # title or a reason (constitution §4.12). There is no second attempt.
  defp attempt(kind, %Listing{id: listing_id}, send) do
    case send.() do
      {:ok, _email} -> :sent
      {:error, _reason} -> email_failed(kind, listing_id)
    end
  rescue
    _exception -> email_failed(kind, listing_id)
  catch
    _kind, _value -> email_failed(kind, listing_id)
  end

  defp email_failed(kind, listing_id) do
    Logger.warning("Listing email not sent: kind=#{kind} listing_id=#{listing_id}")
    :failed
  end

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
