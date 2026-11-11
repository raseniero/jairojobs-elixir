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
end
