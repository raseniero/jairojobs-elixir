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
  A changeset for the region form.
  """
  def change_region(%Region{} = region, attrs \\ %{}) do
    Region.create_changeset(region, attrs)
  end

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

  defp authorize(scope) do
    if Scope.admin?(scope), do: :ok, else: {:error, :unauthorized}
  end
end
