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
  Puts a listing into `status` by updating the row directly.

  **Test-only, on purpose** (spec 003 plan, decision 1): Published, Rejected
  and Taken down are reached through Admin actions that arrive with spec 004.
  Until then this is the only way to get such listings; spec 004 replaces it
  with the real approve / reject / take-down functions. The database CHECK
  constraints still apply, so the listing must be complete.

  Options: `:reason` for `:rejected`.
  """
  def set_listing_status(%Listings.Listing{} = listing, status, opts \\ []) do
    owner = Accounts.get_user!(listing.user_id)
    now = DateTime.utc_now()

    listing
    |> Ecto.Changeset.change(
      status: status,
      business_name: listing.business_name || owner.business_name,
      business_about: listing.business_about || owner.business_about,
      submitted_at: listing.submitted_at || now,
      rejection_reason: if(status == :rejected, do: opts[:reason] || "Needs more detail"),
      closed_at: if(status == :closed, do: now)
    )
    |> Jairojobs.Repo.update!()
    |> Jairojobs.Repo.preload(:region, force: true)
  end

  @doc """
  A complete listing owned by `scope`, put straight into `status` (see
  `set_listing_status/3`).
  """
  def listing_in_status_fixture(scope, status, attrs \\ %{}) do
    listing = listing_fixture(scope, complete_listing_attrs(attrs))
    if status == :draft, do: listing, else: set_listing_status(listing, status)
  end
end
