defmodule Jairojobs.RegionsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Jairojobs.Regions` context.
  """

  alias Jairojobs.AccountsFixtures
  alias Jairojobs.Regions

  def unique_region_name, do: "Region #{System.unique_integer([:positive])}"

  @doc """
  A region created through the real context function by an admin (spec 002).
  """
  def region_fixture(attrs \\ %{}) do
    {:ok, region} =
      attrs
      |> Enum.into(%{name: unique_region_name()})
      |> then(&Regions.create_region(AccountsFixtures.admin_scope_fixture(), &1))

    region
  end
end
