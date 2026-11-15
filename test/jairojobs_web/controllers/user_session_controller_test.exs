defmodule JairojobsWeb.UserSessionControllerTest do
  use JairojobsWeb.ConnCase, async: true

  import Jairojobs.AccountsFixtures
  alias Jairojobs.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "REQ-001-5: log in with email and password", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "REQ-001-5: log in with remember me sets a cookie", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_jairojobs_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "REQ-001-1: log in returns to the originally requested page", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "REQ-001-1: protected page redirects and returns after login", %{
      conn: conn,
      user: user
    } do
      user = set_password(user)

      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert get_session(conn, :user_token)
    end

    test "REQ-001-5: wrong password shows a generic error", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "REQ-001-5: password login requires confirmed email", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "REQ-001-4: magic link logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "REQ-001-3: first link confirms and logs in", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "REQ-001-3: expired or used link: an expired link does not log in", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {token, hashed_token} = generate_user_magic_link_token(user)
      offset_user_token(hashed_token, -16, :minute)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      refute Accounts.get_user!(user.id).confirmed_at
    end

    test "REQ-001-4: used or expired link: a used link does not log in again", %{
      conn: conn,
      user: user
    } do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
      assert get_session(conn, :user_token)

      conn = build_conn() |> post(~p"/users/log-in", %{"user" => %{"token" => token}})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "REQ-001-4: invalid magic link does not log in", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "REQ-001-8: log out invalidates the session", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "REQ-001-8: log out succeeds for a visitor", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  # spec 001, amended 2026-11-13: Settings opens within 10 minutes of logging in; a change
  # submitted from an open page is accepted until 20 minutes after log-in. After that the
  # user is asked to log in again and nothing changes (it used to crash).
  describe "POST /users/update-password" do
    defp logged_in(conn, user, minutes_ago) do
      log_in_user(conn, user,
        token_authenticated_at: DateTime.add(DateTime.utc_now(), -minutes_ago, :minute)
      )
    end

    test "REQ-001-7: change password", %{conn: conn, user: user} do
      conn =
        conn
        |> logged_in(user, 1)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password updated successfully"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "REQ-001-7: a change submitted within 20 minutes of logging in is accepted", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> logged_in(user, 19)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/settings"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "REQ-001-7: a change submitted too late asks to log in again", %{conn: conn, user: user} do
      conn =
        conn
        |> logged_in(user, 21)
        |> post(~p"/users/update-password", %{
          "user" => %{
            "email" => user.email,
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must re-authenticate to access this page."

      refute Accounts.get_user_by_email_and_password(user.email, "new valid password")
      # the session is kept: logging in again is a re-authentication, not a fresh start
      assert get_session(conn, :user_token)
    end
  end
end
