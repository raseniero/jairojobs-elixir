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

  describe "rename_region/3" do
    test "REQ-002-3: rename keeps the slug", %{admin: admin} do
      region = region_fixture(name: "Davao")

      assert {:ok, renamed} = Regions.rename_region(admin, region, %{name: " Davao City "})
      assert renamed.name == "Davao City"
      assert renamed.slug == "davao"
      assert Enum.map(Regions.list_regions(), &{&1.name, &1.slug}) == [{"Davao City", "davao"}]
    end

    test "REQ-002-3: rename to an existing name", %{admin: admin} do
      region_fixture(name: "Cebu")
      davao = region_fixture(name: "Davao City")

      for name <- ["Cebu", "cebu "] do
        assert {:error, changeset} = Regions.rename_region(admin, davao, %{name: name})
        assert "is already a region" in errors_on(changeset).name
      end

      assert Regions.get_region!(davao.id).name == "Davao City"
    end

    test "REQ-002-3: blank or too-long name is rejected", %{admin: admin} do
      region = region_fixture(name: "Davao City")

      assert {:error, changeset} = Regions.rename_region(admin, region, %{name: " "})
      assert "can't be blank" in errors_on(changeset).name

      assert {:error, changeset} =
               Regions.rename_region(admin, region, %{name: String.duplicate("a", 81)})

      assert "should be at most 80 character(s)" in errors_on(changeset).name
    end

    test "REQ-002-3: a region can keep its own name with different casing", %{admin: admin} do
      region = region_fixture(name: "davao city")

      assert {:ok, renamed} = Regions.rename_region(admin, region, %{name: "Davao City"})
      assert renamed.name == "Davao City"
    end

    test "REQ-002-3: slug and active cannot be changed by a rename", %{admin: admin} do
      region = region_fixture(name: "Davao")

      assert {:ok, renamed} =
               Regions.rename_region(admin, region, %{
                 name: "Davao City",
                 slug: "forged",
                 active: false
               })

      assert renamed.slug == "davao"
      assert renamed.active
    end

    test "REQ-002-3: non-admin scopes cannot rename" do
      region = region_fixture(name: "Davao")

      for scope <- non_admin_scopes() do
        assert {:error, :unauthorized} = Regions.rename_region(scope, region, %{name: "Other"})
      end

      assert Regions.get_region!(region.id).name == "Davao"
    end
  end

  describe "hide_region/2 and show_region/2" do
    test "REQ-002-4: hide a region", %{admin: admin} do
      region = region_fixture(name: "Baguio")

      assert {:ok, hidden} = Regions.hide_region(admin, region)
      refute hidden.active
      refute Regions.get_region!(region.id).active
      assert Regions.list_active_regions() == []
    end

    test "REQ-002-4: unhide a region", %{admin: admin} do
      region = region_fixture(name: "Baguio", active: false)

      assert {:ok, shown} = Regions.show_region(admin, region)
      assert shown.active
      assert Regions.list_active_regions() == [shown]
    end

    test "REQ-002-4: hidden region keeps its data", %{admin: admin} do
      region = region_fixture(name: "Baguio")

      assert {:ok, hidden} = Regions.hide_region(admin, region)

      # Its listings are covered in spec 003, once listings exist.
      assert %{hidden | active: true} == %{region | updated_at: hidden.updated_at}
      assert Regions.list_regions() == [hidden]
      assert Regions.get_region_by_slug("baguio") == hidden
    end

    test "REQ-002-4: hiding or showing twice is harmless", %{admin: admin} do
      region = region_fixture(name: "Baguio")

      assert {:ok, hidden} = Regions.hide_region(admin, region)
      assert {:ok, %Region{active: false}} = Regions.hide_region(admin, hidden)
      assert {:ok, shown} = Regions.show_region(admin, hidden)
      assert {:ok, %Region{active: true}} = Regions.show_region(admin, shown)
    end

    test "REQ-002-4: a hidden region can still be renamed", %{admin: admin} do
      region = region_fixture(name: "Baguio", active: false)

      assert {:ok, renamed} = Regions.rename_region(admin, region, %{name: "Baguio City"})
      assert renamed.slug == "baguio"
      refute renamed.active
    end

    test "REQ-002-4: non-admin scopes cannot hide or show" do
      active = region_fixture()
      hidden = region_fixture(active: false)

      for scope <- non_admin_scopes() do
        assert {:error, :unauthorized} = Regions.hide_region(scope, active)
        assert {:error, :unauthorized} = Regions.show_region(scope, hidden)
      end

      assert Regions.get_region!(active.id).active
      refute Regions.get_region!(hidden.id).active
    end
  end

  describe "list_active_regions/0" do
    test "REQ-002-6: only active regions are offered" do
      region_fixture(name: "Davao City")
      region_fixture(name: "Cebu")
      region_fixture(name: "Baguio", active: false)

      assert Enum.map(Regions.list_active_regions(), & &1.name) == ["Cebu", "Davao City"]
    end
  end

  describe "get_region_by_slug/1" do
    test "REQ-002-6: lookup by slug works for hidden regions" do
      hidden = region_fixture(name: "Baguio", active: false)
      active = region_fixture(name: "Cebu")

      assert Regions.get_region_by_slug("baguio") == hidden
      assert Regions.get_region_by_slug("cebu") == active
    end

    test "REQ-002-6: unknown slug is not found" do
      assert Regions.get_region_by_slug("nowhere") == nil
    end
  end

  describe "get_region!/1" do
    test "returns the region or raises" do
      region = region_fixture()
      assert Regions.get_region!(region.id) == region
      assert_raise Ecto.NoResultsError, fn -> Regions.get_region!(Ecto.UUID.generate()) end
    end
  end

  describe "change_region/2" do
    test "returns a changeset for the form" do
      assert %Ecto.Changeset{} = changeset = Regions.change_region(%Region{}, %{name: "Naga"})
      assert Ecto.Changeset.get_field(changeset, :slug) == "naga"
    end

    test "keeps the slug of an existing region" do
      region = region_fixture(name: "Naga")
      changeset = Regions.change_region(region, %{name: "Naga City"})
      assert Ecto.Changeset.get_field(changeset, :slug) == "naga"
    end
  end
end
