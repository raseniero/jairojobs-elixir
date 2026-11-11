defmodule Jairojobs.Regions.Region do
  @moduledoc """
  A supported geographic area (spec 002), e.g. Davao City, Cebu, Metro Manila.

  The `slug` is derived from the name once, at creation, and never changes
  afterwards so shared links keep working (REQ-002-3). `active: false` means
  the region is hidden: it is no longer offered to users but still resolves
  by slug (REQ-002-4, REQ-002-6).
  """
  use Jairojobs.Schema
  import Ecto.Changeset

  @max_name_length 80

  schema "regions" do
    field :name, :string
    field :slug, :string
    field :active, :boolean, default: true

    timestamps()
  end

  @doc """
  Changeset for adding a region (REQ-002-2): trims and validates the name and
  derives the slug from it. `slug` and `active` are never cast from params.
  """
  def create_changeset(region, attrs) do
    region
    |> cast(attrs, [:name])
    |> validate_name()
    |> put_slug()
    |> unique_constraint(:slug,
      error_key: :name,
      message: "makes a web address another region already uses"
    )
  end

  @doc """
  Changeset for renaming a region (REQ-002-3). Only the name is cast, so the
  slug stays exactly as it was created.
  """
  def rename_changeset(region, attrs) do
    region
    |> cast(attrs, [:name])
    |> validate_name()
  end

  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: @max_name_length)
    |> unique_constraint(:name, message: "is already used by another region")
  end

  # A blank value on an existing region is cast to a `nil` change.
  defp trim(nil), do: nil
  defp trim(name), do: String.trim(name)

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        case slugify(name) do
          "" -> add_error(changeset, :name, "needs at least one letter or number")
          slug -> put_change(changeset, :slug, slug)
        end
    end
  end

  @doc """
  Derives a URL-safe slug: lowercase ASCII letters, digits and hyphens only.

      iex> Jairojobs.Regions.Region.slugify("Parañaque City")
      "paranaque-city"
  """
  def slugify(name) when is_binary(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
