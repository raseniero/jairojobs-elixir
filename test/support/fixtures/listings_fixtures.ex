defmodule Jairojobs.ListingsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Jairojobs.Listings` context.
  """

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias Jairojobs.AccountsFixtures
  alias Jairojobs.Listings
  alias Jairojobs.RegionsFixtures

  def unique_business_name, do: "Business #{System.unique_integer([:positive])}"
  def unique_listing_title, do: "Barista #{System.unique_integer([:positive])}"

  @doc """
  The scope of an Employer who has saved business details (REQ-003-2).
  """
  def employer_scope_fixture(attrs \\ %{}) do
    AccountsFixtures.user_fixture(role: "employer")
    |> Scope.for_user()
    |> with_business_details(attrs)
  end

  @doc """
  The scope of an Admin who has saved business details.
  """
  def admin_poster_scope_fixture(attrs \\ %{}) do
    AccountsFixtures.admin_scope_fixture() |> with_business_details(attrs)
  end

  defp with_business_details(scope, attrs) do
    {:ok, user} =
      attrs
      |> Enum.into(%{business_name: unique_business_name()})
      |> then(&Accounts.update_business_details(scope, &1))

    Scope.for_user(user)
  end

  @doc """
  Attributes of a listing that is complete (REQ-003-4). Creates an active
  region unless `:region_id` is given.
  """
  def complete_listing_attrs(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Map.merge(
      %{
        title: unique_listing_title(),
        region_id: attrs[:region_id] || RegionsFixtures.region_fixture().id,
        area: "Matina",
        salary_min: 14_000,
        salary_max: 16_000,
        employment_type: :full_time,
        schedule: "Shifting, 6 days",
        description:
          "We're a neighbourhood café looking for a barista who enjoys talking to regulars.",
        requirements: "At least 18 years old",
        benefits: "Free meals on shift"
      },
      attrs
    )
  end

  @doc """
  A Draft created through the real context function. With no attributes it
  has only a title; pass `complete_listing_attrs()` for a complete one.
  """
  def listing_fixture(scope, attrs \\ %{}) do
    {:ok, listing} =
      attrs
      |> Enum.into(%{title: unique_listing_title()})
      |> then(&Listings.create_listing(scope, &1))

    listing
  end

  @doc """
  Approves a Pending listing as an Admin would, through the real context
  function (spec 004). A throwaway Admin makes the decision.
  """
  def approve_listing_fixture(%Listings.Listing{} = listing) do
    {:ok, listing, _email} =
      Listings.approve_listing(AccountsFixtures.admin_scope_fixture(), listing, &owner_url/1)

    flush_emails()
    listing
  end

  @doc """
  Rejects a Pending listing with `reason`, through the real context function.
  """
  def reject_listing_fixture(%Listings.Listing{} = listing, reason \\ "Needs more detail") do
    {:ok, listing, _email} =
      Listings.reject_listing(
        AccountsFixtures.admin_scope_fixture(),
        listing,
        %{reason: reason},
        &owner_url/1
      )

    flush_emails()
    listing
  end

  @doc """
  Takes a Published listing down with `reason`, through the real context
  function.
  """
  def take_down_listing_fixture(
        %Listings.Listing{} = listing,
        reason \\ "No longer suitable for the board"
      ) do
    {:ok, listing, _email} =
      Listings.take_down_listing(
        AccountsFixtures.admin_scope_fixture(),
        listing,
        %{reason: reason},
        &owner_url/1
      )

    flush_emails()
    listing
  end

  defp owner_url(listing), do: "https://jairojobs.test/my/listings/#{listing.id}"

  @doc """
  The address of a listing's Admin view, as the screens pass it to
  `Listings.submit_listing/3` for the email to Admins (REQ-004-10).
  """
  def admin_url(listing), do: "https://jairojobs.test/admin/listings/#{listing.id}"

  @doc """
  Empties the test process's mailbox of delivered emails.

  Getting a listing into a status sends real emails (spec 004). The fixtures
  call this before returning, so a test's `assert_email_sent` and
  `refute_email_sent` only see emails from the test's own steps.
  """
  def flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  @doc """
  A complete listing owned by `scope`, taken to `status` the way a real
  listing gets there: its owner submits it, an Admin approves, rejects or
  takes it down, its owner closes it.

  The free-tier limit applies on the way, as it does for a real Employer: a
  listing passes through Pending, so `scope` must have a place free.
  """
  def listing_in_status_fixture(scope, status, attrs \\ %{}) do
    scope
    |> listing_fixture(complete_listing_attrs(attrs))
    |> reach(scope, status)
  end

  defp reach(draft, _scope, :draft), do: draft

  defp reach(draft, scope, :pending) do
    {:ok, pending} = Listings.submit_listing(scope, draft, &admin_url/1)
    pending
  end

  defp reach(draft, scope, :published),
    do: draft |> reach(scope, :pending) |> approve_listing_fixture()

  defp reach(draft, scope, :rejected),
    do: draft |> reach(scope, :pending) |> reject_listing_fixture()

  defp reach(draft, scope, :closed) do
    {:ok, closed} = Listings.close_listing(scope, reach(draft, scope, :published))
    closed
  end

  defp reach(draft, scope, :taken_down),
    do: draft |> reach(scope, :published) |> take_down_listing_fixture()
end
