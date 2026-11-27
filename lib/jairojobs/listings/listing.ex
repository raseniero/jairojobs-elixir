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
    field :takedown_reason, :string
    field :submitted_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    # spec 004: `published_at` is set once, on approval. `decided_at` / `decided_by`
    # are the latest Admin decision; what it was follows from the status.
    field :published_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec
    # spec 005: the listing's part of its public address, /jobs/<region slug>/<slug>.
    # Set on approval; changes only when an Admin moves the listing to another region.
    field :slug, :string

    belongs_to :user, User
    belongs_to :region, Region
    belongs_to :decided_by, User

    timestamps()
  end

  def statuses, do: @statuses
  def employment_types, do: @employment_types

  @doc """
  Changeset for saving or editing a draft (REQ-003-3, REQ-003-5). Only the
  title is required; any other field that is filled in must be valid. Status,
  owner, business details, rejection reason, timestamps and the public slug
  are never cast.
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

  @required_to_submit [:region, :area, :salary, :employment_type, :description]
  @min_description 50

  @doc """
  The required parts a listing still lacks before it can be submitted
  (REQ-003-4), in the order the form shows them. `[]` means it is complete.
  `:salary` stands for both ends of the range; `:description` ("About the
  job") is also reported while it is shorter than 50 characters.
  """
  def missing_fields(%__MODULE__{} = listing) do
    Enum.reject(@required_to_submit, &present?(listing, &1))
  end

  defp present?(listing, :region), do: not is_nil(listing.region_id)

  defp present?(listing, :salary),
    do: is_integer(listing.salary_min) and is_integer(listing.salary_max)

  defp present?(listing, :description),
    do: is_binary(listing.description) and String.length(listing.description) >= @min_description

  defp present?(listing, field), do: not is_nil(Map.fetch!(listing, field))

  @doc """
  Changeset that moves a complete Draft or Rejected listing to Pending
  (REQ-003-6): stamps the submission time, clears any rejection reason and
  previous decision (REQ-004-4), and copies the owner's business details onto
  the listing (REQ-003-2).
  """
  def submit_changeset(%__MODULE__{} = listing, %User{} = owner, %DateTime{} = now) do
    listing
    |> change(
      status: :pending,
      submitted_at: now,
      rejection_reason: nil,
      decided_at: nil,
      decided_by_id: nil,
      business_name: owner.business_name,
      business_about: owner.business_about
    )
    |> check_constraint(:status, name: :listings_complete_unless_unsubmitted)
  end

  @doc """
  Changeset for an Admin's fix to a Pending or Published listing (REQ-004-8).

  Every field of the listing form plus this listing's own copy of the business
  name and "about". Unlike a draft, the listing must stay complete: the rules
  of REQ-003-4 and REQ-003-2 apply with every required field present. Status,
  owner, the times and the decision are never cast.
  """
  def admin_changeset(%__MODULE__{} = listing, attrs) do
    listing
    |> draft_changeset(attrs)
    |> cast(attrs, [:business_name, :business_about])
    |> trim([:business_name, :business_about])
    |> validate_required([
      :region_id,
      :area,
      :salary_min,
      :salary_max,
      :employment_type,
      :description,
      :business_name
    ])
    |> validate_length(:description, min: @min_description)
    |> validate_length(:business_name, min: 2, max: 80)
    |> validate_length(:business_about, max: 500)
    |> check_constraint(:status, name: :listings_complete_unless_unsubmitted)
  end

  @reason_types %{reason: :string}

  @doc """
  Changeset for the reason an Admin gives when rejecting or taking down a
  listing (REQ-004-6, REQ-004-7): plain text, trimmed, 10–500 characters. It
  is written for the Employer, who sees it.
  """
  def reason_changeset(attrs) do
    {%{}, @reason_types}
    |> cast(attrs, [:reason])
    |> trim([:reason])
    |> validate_required([:reason])
    |> validate_length(:reason, min: 10, max: 500)
  end

  @doc """
  Changeset that publishes a Pending listing (REQ-004-5). Nothing the Employer
  wrote is changed; only the status, the record of the decision, and `slug`:
  the listing's part of its public address (REQ-005-6), which the context has
  already recorded as taken.
  """
  def approve_changeset(%__MODULE__{} = listing, %User{} = admin, slug, %DateTime{} = now)
      when is_binary(slug) do
    listing
    |> change(status: :published, published_at: now, slug: slug)
    |> decided(admin, now)
  end

  @doc """
  Changeset that sends a Pending listing back to its Employer with `reason`
  (REQ-004-6).
  """
  def reject_changeset(%__MODULE__{} = listing, %User{} = admin, reason, %DateTime{} = now)
      when is_binary(reason) do
    listing
    |> change(status: :rejected, rejection_reason: reason)
    |> decided(admin, now)
  end

  @doc """
  Changeset that takes a Published listing down for good with `reason`
  (REQ-004-7). `published_at` is kept.
  """
  def take_down_changeset(%__MODULE__{} = listing, %User{} = admin, reason, %DateTime{} = now)
      when is_binary(reason) do
    listing
    |> change(status: :taken_down, takedown_reason: reason)
    |> decided(admin, now)
  end

  # The latest decision: when, and by which Admin (REQ-004-4).
  defp decided(changeset, %User{id: admin_id}, now) do
    changeset
    |> change(decided_at: now, decided_by_id: admin_id)
    |> check_constraint(:status, name: :listings_complete_unless_unsubmitted)
    |> check_constraint(:published_at, name: :listings_published_has_time)
    |> check_constraint(:rejection_reason, name: :listings_rejected_has_reason)
    |> check_constraint(:takedown_reason, name: :listings_taken_down_has_reason)
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
