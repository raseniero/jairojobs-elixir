defmodule Jairojobs.Regions do
  @moduledoc """
  The admin-managed list of supported regions (spec 002).

  Reads take no scope: a region's name, slug and active flag are not private.
  Writes take the current scope first and are refused with
  `{:error, :unauthorized}` unless it belongs to an Admin.
  """

  import Ecto.Query, warn: false

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Regions.Region
  alias Jairojobs.Repo

  @doc """
  Every region, active and hidden, in alphabetical order (REQ-002-1).
  """
  def list_regions do
    Repo.all(from r in Region, order_by: [asc: r.name])
  end

  @doc """
  The regions to offer users — active only, in alphabetical order
  (REQ-002-6). This is what listing forms, public browse and alerts consume.
  """
  def list_active_regions do
    Repo.all(from r in Region, where: r.active, order_by: [asc: r.name])
  end

  @doc """
  Looks a region up by slug, whether it is active or hidden, so old links and
  existing listings keep resolving (REQ-002-6). Returns `nil` when unknown.
  """
  def get_region_by_slug(slug) when is_binary(slug), do: Repo.get_by(Region, slug: slug)

  @doc """
  A changeset for the region form.
  """
  def change_region(region, attrs \\ %{})

  def change_region(%Region{id: nil} = region, attrs), do: Region.create_changeset(region, attrs)
  def change_region(%Region{} = region, attrs), do: Region.rename_changeset(region, attrs)

  @doc """
  Gets a region by id (admin URLs use the UUID). Raises if it does not exist.
  """
  def get_region!(id), do: Repo.get!(Region, id)

  @doc """
  Adds a region; it starts active and its slug is derived from the name
  (REQ-002-2). Returns:

    * `{:ok, region}`
    * `{:error, changeset}` — blank, too long, duplicate name or slug collision
    * `{:error, :unauthorized}` — the scope is not an Admin
  """
  def create_region(scope, attrs) do
    with :ok <- authorize(scope) do
      %Region{}
      |> Region.create_changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Renames a region; the slug never changes (REQ-002-3). Returns the same
  shapes as `create_region/2`.
  """
  def rename_region(scope, %Region{} = region, attrs) do
    with :ok <- authorize(scope) do
      region
      |> Region.rename_changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Hides a region: it is no longer offered to users but keeps its data and
  still resolves by slug (REQ-002-4). There is no delete.

  Returns `{:ok, region}` or `{:error, :unauthorized}`.
  """
  def hide_region(scope, %Region{} = region), do: set_active(scope, region, false)

  @doc """
  Makes a hidden region active again (REQ-002-4).

  Returns `{:ok, region}` or `{:error, :unauthorized}`.
  """
  def show_region(scope, %Region{} = region), do: set_active(scope, region, true)

  defp set_active(scope, region, active) do
    with :ok <- authorize(scope) do
      region
      |> Ecto.Changeset.change(active: active)
      |> Repo.update()
    end
  end

  defp authorize(scope) do
    if Scope.admin?(scope), do: :ok, else: {:error, :unauthorized}
  end
end
