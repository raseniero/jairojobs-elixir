defmodule Jairojobs.RegionsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Jairojobs.Regions` context.
  """

  alias Jairojobs.AccountsFixtures
  alias Jairojobs.Regions

  def unique_region_name, do: "Region #{System.unique_integer([:positive])}"

  @doc """
  A region created through the real context function by an admin (spec 002).

  Pass `active: false` for a hidden region.
  """
  def region_fixture(attrs \\ %{}) do
    {active, attrs} = attrs |> Map.new() |> Map.pop(:active, true)
    scope = AccountsFixtures.admin_scope_fixture()

    {:ok, region} =
      attrs
      |> Enum.into(%{name: unique_region_name()})
      |> then(&Regions.create_region(scope, &1))

    if active do
      region
    else
      {:ok, region} = Regions.hide_region(scope, region)
      region
    end
  end
end
