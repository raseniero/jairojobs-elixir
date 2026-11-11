defmodule Jairojobs.RegionsTest do
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Accounts.Scope
  alias Jairojobs.Regions
  alias Jairojobs.Regions.Region

  # Scopes the context must refuse for every write (constitution §2.7, §3.4).
  defp non_admin_scopes do
    [
      Scope.for_user(user_fixture(role: "candidate")),
      Scope.for_user(user_fixture(role: "employer")),
      nil,
      Scope.system()
    ]
  end

  setup do
    %{admin: admin_scope_fixture()}
  end

  describe "create_region/2" do
    test "REQ-002-2: add a region", %{admin: admin} do
      assert {:ok, %Region{} = region} = Regions.create_region(admin, %{name: "Iloilo City"})
      assert region.name == "Iloilo City"
      assert region.slug == "iloilo-city"
      assert region.active
      assert region in Regions.list_regions()
    end

    test "REQ-002-2: duplicate name", %{admin: admin} do
      region_fixture(name: "Cebu")

      for name <- ["cebu", " Cebu ", "CEBU"] do
        assert {:error, changeset} = Regions.create_region(admin, %{name: name})
        assert errors_on(changeset).name != []
      end

      assert [%Region{name: "Cebu"}] = Regions.list_regions()
    end

    test "REQ-002-2: blank or too-long name", %{admin: admin} do
      for name <- ["", "   ", nil] do
        assert {:error, changeset} = Regions.create_region(admin, %{name: name})
        assert "can't be blank" in errors_on(changeset).name
      end

      assert {:error, changeset} =
               Regions.create_region(admin, %{name: String.duplicate("a", 81)})

      assert "should be at most 80 character(s)" in errors_on(changeset).name

      assert {:ok, _region} = Regions.create_region(admin, %{name: String.duplicate("a", 80)})
    end

    test "REQ-002-2: slug collision", %{admin: admin} do
      region_fixture(name: "Cebu")

      assert {:error, changeset} = Regions.create_region(admin, %{name: "Cebu!"})

      assert "makes a web address that another region already uses" in errors_on(changeset).name

      assert [%Region{name: "Cebu"}] = Regions.list_regions()
    end

    test "REQ-002-2: name is trimmed", %{admin: admin} do
      assert {:ok, region} = Regions.create_region(admin, %{name: "  Baguio  "})
      assert region.name == "Baguio"
      assert region.slug == "baguio"
    end

    test "REQ-002-2: slug uses only lowercase ASCII letters, digits and hyphens", %{admin: admin} do
      for {name, slug} <- [
            {"Parañaque", "paranaque"},
            {"General Santos (GenSan)", "general-santos-gensan"},
            {"  Cagayan   de -- Oro ", "cagayan-de-oro"},
            {"Zone 7", "zone-7"}
          ] do
        assert {:ok, region} = Regions.create_region(admin, %{name: name})
        assert region.slug == slug
      end
    end

    test "REQ-002-2: a name with no letters or digits is rejected", %{admin: admin} do
      assert {:error, changeset} = Regions.create_region(admin, %{name: "!!!"})
      assert "must contain at least one letter or number" in errors_on(changeset).name
    end

    test "REQ-002-2: slug and active cannot be set from params", %{admin: admin} do
      assert {:ok, region} =
               Regions.create_region(admin, %{name: "Bacolod", slug: "forged", active: false})

      assert region.slug == "bacolod"
      assert region.active
    end

    test "REQ-002-2: non-admin scopes cannot add a region" do
      for scope <- non_admin_scopes() do
        assert {:error, :unauthorized} = Regions.create_region(scope, %{name: "Iloilo City"})
      end

      assert Regions.list_regions() == []
    end
  end

  describe "list_regions/0" do
    test "REQ-002-1: admin sees all regions" do
      region_fixture(name: "Davao City")
      region_fixture(name: "cebu")
      region_fixture(name: "Baguio")

      assert Enum.map(Regions.list_regions(), & &1.name) == ["Baguio", "cebu", "Davao City"]
    end
  end

  describe "change_region/2" do
    test "returns a changeset for the form" do
      assert %Ecto.Changeset{} = changeset = Regions.change_region(%Region{}, %{name: "Naga"})
      assert Ecto.Changeset.get_field(changeset, :slug) == "naga"
    end
  end
end
