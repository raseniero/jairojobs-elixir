defmodule JairojobsWeb.PageControllerTest do
  use JairojobsWeb.ConnCase, async: true

  import Jairojobs.AccountsFixtures

  test "REQ-001-1: public home page renders without login", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ ~s(id="home")
    refute get_session(conn, :user_token)
  end

  describe "REQ-001-12: navigation on the home page" do
    test "visitor sees Log in and Sign up", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="nav-login")
      assert html =~ ~s(id="nav-signup")
      refute html =~ ~s(id="nav-settings")
    end

    test "candidate sees applications, profile and settings", %{conn: conn} do
      html =
        conn |> log_in_user(user_fixture(role: "candidate")) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="nav-applications")
      assert html =~ ~s(id="nav-profile")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-admin")
    end

    test "employer sees listings, post a job and settings", %{conn: conn} do
      html =
        conn |> log_in_user(user_fixture(role: "employer")) |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="nav-listings")
      assert html =~ ~s(id="nav-post-job")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-admin")
    end

    test "admin additionally sees Admin", %{conn: conn} do
      html = conn |> log_in_user(admin_fixture()) |> get(~p"/") |> html_response(200)
      assert html =~ ~s(id="nav-admin")
      assert html =~ ~s(id="nav-settings")
      refute html =~ ~s(id="nav-applications")
      refute html =~ ~s(id="nav-listings")
    end
  end
end
