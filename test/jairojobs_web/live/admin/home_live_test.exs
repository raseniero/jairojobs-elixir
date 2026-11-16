defmodule JairojobsWeb.Admin.HomeLiveTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures
  import Jairojobs.ListingsFixtures

  describe "admin home" do
    test "REQ-002-1: admin area lists Regions", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

      assert has_element?(view, "#admin-sections #admin-section-regions")
    end

    test "REQ-004-2: the Admin area shows how many are waiting", %{conn: conn} do
      for _ <- 1..2, do: listing_in_status_fixture(employer_scope_fixture(), :pending)
      listing_in_status_fixture(employer_scope_fixture(), :published)
      listing_fixture(employer_scope_fixture())

      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

      assert view |> element("#admin-listings-waiting") |> render() =~ "2 waiting for approval"
    end

    test "REQ-004-2: nothing waiting", %{conn: conn} do
      listing_in_status_fixture(employer_scope_fixture(), :published)

      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

      assert view |> element("#admin-listings-waiting") |> render() =~ "Nothing waiting"
    end

    test "Listings is the first row, above Regions (spec 004, plan decision 13)", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#admin-sections a")
        |> LazyHTML.attribute("id")

      assert ids == [
               "admin-section-listings",
               "admin-section-regions",
               "admin-section-my-listings",
               "admin-section-post-a-job"
             ]
    end

    test "REQ-002-1: non-admin is refused", %{conn: conn} do
      for role <- ["candidate", "employer"] do
        conn = log_in_user(conn, user_fixture(role: role))

        assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin")
        assert flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-002-1: visitor is redirected to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
    end
  end
end
