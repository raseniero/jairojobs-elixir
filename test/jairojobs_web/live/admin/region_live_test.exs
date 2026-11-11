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

    test "REQ-002-2: non-admin cannot open the new-region form", %{conn: conn} do
      for role <- ["candidate", "employer"] do
        conn = log_in_user(conn, user_fixture(role: role))
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/regions/new")
      end

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/regions/new")
    end

    test "REQ-002-3: non-admin cannot open the edit form", %{conn: conn} do
      region = region_fixture()

      for role <- ["candidate", "employer"] do
        conn = log_in_user(conn, user_fixture(role: role))

        assert {:error, {:redirect, %{to: "/"}}} =
                 live(conn, ~p"/admin/regions/#{region.id}/edit")
      end

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/regions/#{region.id}/edit")
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

  describe "new region" do
    setup :log_in_admin

    test "REQ-002-2: add a region", %{conn: conn} do
      region_fixture(name: "Cebu")
      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      {:ok, form_view, _html} =
        view
        |> element("#add-region")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/regions/new")

      form_view |> form("#region-form", region: %{name: "Iloilo City"}) |> render_change()
      assert has_element?(form_view, "#region-address", "/jobs/iloilo-city")

      {:ok, view, _html} =
        form_view
        |> form("#region-form", region: %{name: "Iloilo City"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/regions")

      iloilo = Regions.get_region_by_slug("iloilo-city")
      assert iloilo.name == "Iloilo City"
      assert iloilo.active

      assert has_element?(view, "#regions-#{iloilo.id}", "Iloilo City")
      refute has_element?(view, "#region-hidden-#{iloilo.id}")
      assert List.last(row_ids(view)) == "regions-#{iloilo.id}"
    end

    test "REQ-002-2: duplicate name", %{conn: conn} do
      region_fixture(name: "Cebu")
      {:ok, view, _html} = live(conn, ~p"/admin/regions/new")

      for name <- ["cebu", " Cebu "] do
        html = view |> form("#region-form", region: %{name: name}) |> render_submit()
        assert html =~ "is already a region"
      end

      assert has_element?(view, "#region-form")
      assert [%{name: "Cebu"}] = Regions.list_regions()
    end

    test "REQ-002-2: blank or too-long name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/regions/new")

      assert view |> form("#region-form", region: %{name: " "}) |> render_change() =~
               "can&#39;t be blank"

      assert view |> form("#region-form", region: %{name: ""}) |> render_submit() =~
               "can&#39;t be blank"

      assert view
             |> form("#region-form", region: %{name: String.duplicate("a", 81)})
             |> render_submit() =~ "should be at most 80 character(s)"

      assert Regions.list_regions() == []
    end

    test "REQ-002-2: slug collision", %{conn: conn} do
      region_fixture(name: "Cebu")
      {:ok, view, _html} = live(conn, ~p"/admin/regions/new")

      assert view |> form("#region-form", region: %{name: "Cebu!"}) |> render_submit() =~
               "makes a web address that another region already uses"

      assert [%{name: "Cebu"}] = Regions.list_regions()
    end

    test "REQ-002-2: cancel goes back to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/regions/new")

      assert {:ok, _view, _html} =
               view
               |> element("#region-form-cancel")
               |> render_click()
               |> follow_redirect(conn, ~p"/admin/regions")

      assert Regions.list_regions() == []
    end
  end

  describe "edit region" do
    setup :log_in_admin

    test "REQ-002-3: rename keeps the slug", %{conn: conn} do
      davao = region_fixture(name: "Davao")
      {:ok, view, _html} = live(conn, ~p"/admin/regions")

      {:ok, form_view, _html} =
        view
        |> element("#edit-region-#{davao.id}")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/regions/#{davao.id}/edit")

      assert has_element?(form_view, "#region-address", "/jobs/davao")

      form_view |> form("#region-form", region: %{name: "Davao City"}) |> render_change()
      assert has_element?(form_view, "#region-address", "/jobs/davao")
      refute has_element?(form_view, "#region-address", "/jobs/davao-city")

      {:ok, view, _html} =
        form_view
        |> form("#region-form", region: %{name: "Davao City"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/regions")

      assert has_element?(view, "#regions-#{davao.id}", "Davao City")
      assert has_element?(view, "#regions-#{davao.id}", "/jobs/davao")
      assert %{name: "Davao City", slug: "davao"} = Regions.get_region!(davao.id)
    end

    test "REQ-002-3: rename to an existing name", %{conn: conn} do
      region_fixture(name: "Cebu")
      davao = region_fixture(name: "Davao City")

      {:ok, view, _html} = live(conn, ~p"/admin/regions/#{davao.id}/edit")

      assert view |> form("#region-form", region: %{name: "Cebu"}) |> render_submit() =~
               "is already a region"

      assert Regions.get_region!(davao.id).name == "Davao City"
    end

    test "REQ-002-3: a hidden region can be renamed and stays hidden", %{conn: conn} do
      baguio = region_fixture(name: "Baguio", active: false)
      {:ok, view, _html} = live(conn, ~p"/admin/regions/#{baguio.id}/edit")

      {:ok, view, _html} =
        view
        |> form("#region-form", region: %{name: "Baguio City"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/regions")

      assert has_element?(view, "#regions-#{baguio.id}", "Baguio City")
      assert has_element?(view, "#region-hidden-#{baguio.id}")
    end

    test "REQ-002-3: an unknown region is not found", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/admin/regions/#{Ecto.UUID.generate()}/edit")
      end
    end
  end
end
