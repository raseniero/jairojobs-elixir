defmodule JairojobsWeb.Admin.HomeLiveTest do
  use JairojobsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Jairojobs.AccountsFixtures

  describe "admin home" do
    test "REQ-002-1: admin area lists Regions as its first section", %{conn: conn} do
      {:ok, view, _html} = conn |> log_in_user(admin_fixture()) |> live(~p"/admin")

      assert has_element?(view, "#admin-sections #admin-section-regions")
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
