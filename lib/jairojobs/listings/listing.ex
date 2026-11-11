defmodule Jairojobs.Listings.Listing do
  @moduledoc """
  A single open position posted by an Employer or Admin (spec 003).

  A listing can be saved as a Draft with only a title; everything else is
  required when it is submitted for approval. The business name and "about"
  are copied from the owner's account at submit, so a later change to the
  account never alters a Pending or Published listing (REQ-003-2).
  """
  use Jairojobs.Schema
  import Ecto.Changeset

  alias Jairojobs.Accounts.User
  alias Jairojobs.Pesos
  alias Jairojobs.Regions.Region

  @statuses [:draft, :pending, :published, :rejected, :closed, :taken_down]
  @employment_types [:full_time, :part_time, :contract, :temporary, :internship]

  @min_salary 1_000
  @max_salary 1_000_000

  schema "listings" do
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :title, :string
    field :area, :string
    field :salary_min, Pesos, source: :salary_min_centavos
    field :salary_max, Pesos, source: :salary_max_centavos
    field :employment_type, Ecto.Enum, values: @employment_types
    field :schedule, :string
    field :description, :string
    field :requirements, :string
    field :benefits, :string
    field :business_name, :string
    field :business_about, :string
    field :rejection_reason, :string
    field :submitted_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    belongs_to :user, User
    belongs_to :region, Region

    timestamps()
  end

  def statuses, do: @statuses
  def employment_types, do: @employment_types

  @doc """
  Changeset for saving or editing a draft (REQ-003-3, REQ-003-5). Only the
  title is required; any other field that is filled in must be valid. Status,
  owner, business details, rejection reason and timestamps are never cast.
  """
  def draft_changeset(listing, attrs) do
    listing
    |> cast(attrs, [
      :title,
      :region_id,
      :area,
      :salary_min,
      :salary_max,
      :employment_type,
      :schedule,
      :description,
      :requirements,
      :benefits
    ])
    |> trim([:title, :area, :schedule, :description, :requirements, :benefits])
    |> validate_required([:title])
    |> validate_length(:title, min: 5, max: 100)
    |> validate_length(:area, max: 80)
    |> validate_length(:schedule, max: 80)
    |> validate_length(:description, max: 5_000)
    |> validate_length(:requirements, max: 3_000)
    |> validate_length(:benefits, max: 3_000)
    |> validate_salary()
    |> foreign_key_constraint(:region_id)
    |> check_constraint(:salary_max, name: :listings_salary_check)
  end

  defp trim(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(changeset, field, fn
        nil -> nil
        value -> blank_to_nil(String.trim(value))
      end)
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A monthly range in whole pesos: both ends or neither, ₱1,000 to ₱1,000,000.
  defp validate_salary(changeset) do
    min = get_field(changeset, :salary_min)
    max = get_field(changeset, :salary_max)

    changeset
    |> validate_number(:salary_min,
      greater_than_or_equal_to: @min_salary,
      message: "must be at least ₱1,000"
    )
    |> validate_number(:salary_max,
      less_than_or_equal_to: @max_salary,
      message: "must be at most ₱1,000,000"
    )
    |> validate_both_ends(min, max)
    |> validate_range(min, max)
  end

  defp validate_both_ends(changeset, min, nil) when is_integer(min),
    do: add_error(changeset, :salary_max, "Enter the maximum as well")

  defp validate_both_ends(changeset, nil, max) when is_integer(max),
    do: add_error(changeset, :salary_min, "Enter the minimum as well")

  defp validate_both_ends(changeset, _min, _max), do: changeset

  defp validate_range(changeset, min, max)
       when is_integer(min) and is_integer(max) and max < min,
       do: add_error(changeset, :salary_max, "The maximum must be at least the minimum")

  defp validate_range(changeset, _min, _max), do: changeset
end
