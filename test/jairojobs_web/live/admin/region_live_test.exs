defmodule JairojobsWeb.Admin.RegionLiveTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.RegionsFixtures

  alias Jairojobs.Regions

  defp log_in_admin(%{conn: conn}) do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  # DOM ids of the region rows, in the order they are rendered.
  defp row_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#regions > li[id^='regions-']")
    |> LazyHTML.attribute("id")
  end

  describe "access" do
    test "REQ-002-1: non-admin is refused", %{conn: conn} do
      for role <- ["candidate", "employer"] do
        conn = log_in_user(conn, user_fixture(role: role))

        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/regions")
        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-002-1: visitor is redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/regions")
    end
  end

  describe "list" do
    setup :log_in_admin

    test "REQ-002-1: admin sees all regions", %{conn: conn} do
      davao = region_fixture(name: "Davao City")
      cebu = region_fixture(name: "Cebu")
      baguio = region_fixture(name: "Baguio", active: false)

      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      assert row_ids(view) == Enum.map([baguio, cebu, davao], &"regions-#{&1.id}")

      assert has_element?(view, "#region-hidden-#{baguio.id}")
      refute has_element?(view, "#region-hidden-#{cebu.id}")
      refute has_element?(view, "#region-hidden-#{davao.id}")

      assert has_element?(view, "#add-region")
      assert has_element?(view, "#edit-region-#{cebu.id}")
      assert has_element?(view, "#regions-#{davao.id}", "/jobs/davao-city")
    end

    test "REQ-002-1: an empty list says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      assert row_ids(view) == []
      assert has_element?(view, "#regions #no-regions")
    end

    test "REQ-002-1: the admin home links to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert {:ok, _view, _html} =
               view
               |> element("#admin-section-regions")
               |> render_click()
               |> follow_redirect(conn, ~p"/admin/regions")
    end

    test "REQ-002-4: hide a region", %{conn: conn} do
      baguio = region_fixture(name: "Baguio")
      cebu = region_fixture(name: "Cebu")

      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      assert has_element?(view, "#hide-region-#{baguio.id}")
      refute has_element?(view, "#show-region-#{baguio.id}")

      view |> element("#hide-region-#{baguio.id}") |> render_click()

      assert has_element?(view, "#region-hidden-#{baguio.id}")
      assert has_element?(view, "#show-region-#{baguio.id}")
      refute has_element?(view, "#hide-region-#{baguio.id}")
      assert row_ids(view) == Enum.map([baguio, cebu], &"regions-#{&1.id}")

      assert Enum.map(Regions.list_active_regions(), & &1.name) == ["Cebu"]
    end

    test "REQ-002-4: unhide a region", %{conn: conn} do
      baguio = region_fixture(name: "Baguio", active: false)

      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      view |> element("#show-region-#{baguio.id}") |> render_click()

      refute has_element?(view, "#region-hidden-#{baguio.id}")
      assert has_element?(view, "#hide-region-#{baguio.id}")
      assert Enum.map(Regions.list_active_regions(), & &1.name) == ["Baguio"]
    end
  end
end
