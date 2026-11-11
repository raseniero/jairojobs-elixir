defmodule JairojobsWeb.UserAuthTest do
  use JairojobsWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope
  alias JairojobsWeb.UserAuth

  import Jairojobs.AccountsFixtures

  @remember_me_cookie "_jairojobs_web_user_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, JairojobsWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{user: %{user_fixture() | authenticated_at: DateTime.utc_now()}, conn: conn}
  end

  describe "log_in_user/3" do
    test "REQ-001-4: log in stores the user token in the session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)
      assert get_session(conn, :live_socket_id) == "users_sessions:#{Base.url_encode64(token)}"
      assert redirected_to(conn) == ~p"/"
      assert Accounts.get_user_by_session_token(token)
    end

    test "REQ-001-4: log in clears everything previously stored in the session", %{
      conn: conn,
      user: user
    } do
      conn = conn |> put_session(:to_be_removed, "value") |> UserAuth.log_in_user(user)
      refute get_session(conn, :to_be_removed)
    end

    test "REQ-001-6: re-authenticating the same user keeps the session", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      assert get_session(conn, :to_be_removed)
    end

    test "REQ-001-6: re-authenticating as a different user clears the session", %{
      conn: conn,
      user: user
    } do
      other_user = user_fixture()

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(other_user))
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      refute get_session(conn, :to_be_removed)
    end

    test "REQ-001-4: log in redirects to the configured path", %{conn: conn, user: user} do
      conn = conn |> put_session(:user_return_to, "/hello") |> UserAuth.log_in_user(user)
      assert redirected_to(conn) == "/hello"
    end

    test "REQ-001-1: log in returns to the requested page and clears it from the session", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> put_session(:user_return_to, "/hello")
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == "/hello"
      refute get_session(conn, :user_return_to)
    end

    test "REQ-001-4: remember me writes a cookie", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :user_remember_me) == true

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == @remember_me_cookie_max_age
    end

    test "REQ-001-6: re-authenticating an already logged-in user redirects to settings", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.log_in_user(user)

      assert redirected_to(conn) == ~p"/users/settings"
    end

    test "REQ-001-4: remember me is kept from the previous session", %{conn: conn, user: user} do
      conn = conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :user_remember_me) == true

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, JairojobsWeb.Endpoint.config(:secret_key_base))
        |> fetch_cookies()
        |> init_test_session(%{user_remember_me: true})

      # the conn is already logged in and has the remember_me cookie set,
      # now we log in again and even without explicitly setting remember_me,
      # the cookie should be set again
      conn = conn |> UserAuth.log_in_user(user, %{})
      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :user_token)
      assert max_age == @remember_me_cookie_max_age
      assert get_session(conn, :user_remember_me) == true
    end
  end

  describe "logout_user/1" do
    test "REQ-001-8: log out erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "REQ-001-8: log out disconnects live sockets for the session", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      JairojobsWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "REQ-001-8: log out works even if already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_scope_for_user/2" do
    test "REQ-001-9: scope is built from the session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn |> put_session(:user_token, user_token) |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert get_session(conn, :user_token) == user_token
    end

    test "REQ-001-9: scope is built from the remember-me cookie", %{conn: conn, user: user} do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert get_session(conn, :user_token) == user_token
      assert get_session(conn, :user_remember_me)

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(user_token)}"
    end

    test "REQ-001-9: scope is empty when no session data is present", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_scope_for_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_scope
    end

    test "REQ-001-9: session token is reissued after a few days and cookie refreshed", %{
      conn: conn,
      user: user
    } do
      logged_in_conn =
        conn |> fetch_cookies() |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      offset_user_token(token, -10, :day)
      {user, _} = Accounts.get_user_by_session_token(token)

      conn =
        conn
        |> put_session(:user_token, token)
        |> put_session(:user_remember_me, true)
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
      assert conn.assigns.current_scope.user.authenticated_at == user.authenticated_at
      assert new_token = get_session(conn, :user_token)
      assert new_token != token
      assert %{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert new_signed_token != signed_token
      assert max_age == @remember_me_cookie_max_age
    end
  end

  describe "on_mount :mount_current_scope" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "REQ-001-9: mount_current_scope assigns current_scope from a valid token", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "REQ-001-1: mount_current_scope assigns nil for an invalid token", %{conn: conn} do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end

    test "REQ-001-1: mount_current_scope assigns nil for a visitor", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:mount_current_scope, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_authenticated" do
    test "REQ-001-9: require_authenticated assigns current_scope from a valid token", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_scope.user.id == user.id
    end

    test "REQ-001-1: require_authenticated redirects to log in for an invalid token", %{
      conn: conn
    } do
      user_token = "invalid_token"
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: JairojobsWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end

    test "REQ-001-1: require_authenticated redirects a visitor to log in", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: JairojobsWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} = UserAuth.on_mount(:require_authenticated, %{}, session, socket)
      assert updated_socket.assigns.current_scope == nil
    end
  end

  describe "on_mount :require_sudo_mode" do
    test "REQ-001-6: sudo mode allows users authenticated in the last 10 minutes", %{
      conn: conn,
      user: user
    } do
      user_token = Accounts.generate_user_session_token(user)
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: JairojobsWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:cont, _updated_socket} =
               UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end

    test "REQ-001-6: sudo mode redirects when authentication is too old", %{
      conn: conn,
      user: user
    } do
      eleven_minutes_ago = DateTime.utc_now() |> DateTime.add(-11, :minute)
      user = %{user | authenticated_at: eleven_minutes_ago}
      user_token = Accounts.generate_user_session_token(user)
      {user, token_inserted_at} = Accounts.get_user_by_session_token(user_token)
      assert DateTime.compare(token_inserted_at, user.authenticated_at) == :gt
      session = conn |> put_session(:user_token, user_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: JairojobsWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, _updated_socket} =
               UserAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end
  end

  describe "require_authenticated_user/2" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "REQ-001-1: protected page redirects a visitor to log in", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end

    test "REQ-001-1: protected page stores the return-to path on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "REQ-001-1: protected page renders for an authenticated user", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
      refute conn.status
    end
  end

  ## spec 001 — require_admin (plan decision 7; consumed by specs 004/008)

  describe "on_mount :require_admin" do
    defp live_socket do
      %LiveView.Socket{endpoint: JairojobsWeb.Endpoint, assigns: %{__changed__: %{}, flash: %{}}}
    end

    test "REQ-001-9: admin passes", %{conn: conn} do
      admin = %{admin_fixture() | authenticated_at: DateTime.utc_now()}

      session =
        conn
        |> put_session(:user_token, Accounts.generate_user_session_token(admin))
        |> get_session()

      assert {:cont, socket} = UserAuth.on_mount(:require_admin, %{}, session, live_socket())
      assert socket.assigns.current_scope.user.id == admin.id
    end

    test "REQ-001-9: candidate and employer are refused", %{conn: conn} do
      for role <- ["candidate", "employer"] do
        user = user_fixture(role: role)

        session =
          conn
          |> put_session(:user_token, Accounts.generate_user_session_token(user))
          |> get_session()

        assert {:halt, socket} = UserAuth.on_mount(:require_admin, %{}, session, live_socket())
        assert socket.redirected == {:redirect, %{to: ~p"/", status: 302}}
        assert socket.assigns.flash["error"] == "You are not authorized to access this page."
      end
    end

    test "REQ-001-1: visitor is redirected to log in", %{conn: conn} do
      session = get_session(conn)

      assert {:halt, socket} = UserAuth.on_mount(:require_admin, %{}, session, live_socket())
      assert socket.redirected == {:redirect, %{to: ~p"/users/log-in", status: 302}}
    end
  end

  describe "require_admin/2" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "REQ-001-9: admin passes", %{conn: conn} do
      admin = admin_fixture()

      conn =
        conn
        |> assign(:current_scope, Scope.for_user(admin))
        |> fetch_flash()
        |> UserAuth.require_admin([])

      refute conn.halted
      refute conn.status
    end

    # spec 002, plan decision 1: the plug matches the hook (was a 403 in spec 001).
    test "REQ-002-1: non-admin is refused", %{conn: conn} do
      for role <- ["candidate", "employer"] do
        conn =
          conn
          |> assign(:current_scope, Scope.for_user(user_fixture(role: role)))
          |> fetch_flash()
          |> UserAuth.require_admin([])

        assert conn.halted
        assert redirected_to(conn) == ~p"/"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "You are not authorized to access this page."
      end
    end

    test "REQ-001-1: visitor is redirected to log in", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must log in to access this page."
    end
  end

  ## spec 003 — require_poster: Employers and Admins may post listings (REQ-003-1)

  describe "on_mount :require_poster" do
    test "REQ-003-1: employer and admin pass", %{conn: conn} do
      for user <- [user_fixture(role: "employer"), admin_fixture()] do
        session =
          conn
          |> put_session(:user_token, Accounts.generate_user_session_token(user))
          |> get_session()

        assert {:cont, socket} = UserAuth.on_mount(:require_poster, %{}, session, live_socket())
        assert socket.assigns.current_scope.user.id == user.id
      end
    end

    test "REQ-003-1: candidate is refused", %{conn: conn} do
      session =
        conn
        |> put_session(
          :user_token,
          Accounts.generate_user_session_token(user_fixture(role: "candidate"))
        )
        |> get_session()

      assert {:halt, socket} = UserAuth.on_mount(:require_poster, %{}, session, live_socket())
      assert socket.redirected == {:redirect, %{to: ~p"/", status: 302}}
      assert socket.assigns.flash["error"] == "You are not authorized to access this page."
    end

    test "REQ-003-1: visitor is redirected to log in", %{conn: conn} do
      session = get_session(conn)

      assert {:halt, socket} = UserAuth.on_mount(:require_poster, %{}, session, live_socket())
      assert socket.redirected == {:redirect, %{to: ~p"/users/log-in", status: 302}}
    end
  end

  describe "require_poster/2" do
    setup %{conn: conn} do
      %{conn: UserAuth.fetch_current_scope_for_user(conn, [])}
    end

    test "REQ-003-1: employer and admin pass", %{conn: conn} do
      for user <- [user_fixture(role: "employer"), admin_fixture()] do
        conn =
          conn
          |> assign(:current_scope, Scope.for_user(user))
          |> fetch_flash()
          |> UserAuth.require_poster([])

        refute conn.halted
        refute conn.status
      end
    end

    test "REQ-003-1: candidate is refused", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Scope.for_user(user_fixture(role: "candidate")))
        |> fetch_flash()
        |> UserAuth.require_poster([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You are not authorized to access this page."
    end

    test "REQ-003-1: visitor is redirected to log in", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_poster([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "disconnect_sessions/1" do
    test "REQ-001-7: disconnect_sessions broadcasts a disconnect for each token" do
      tokens = [%{token: "token1"}, %{token: "token2"}]

      for %{token: token} <- tokens do
        JairojobsWeb.Endpoint.subscribe("users_sessions:#{Base.url_encode64(token)}")
      end

      UserAuth.disconnect_sessions(tokens)

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "users_sessions:dG9rZW4x"
      }

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "users_sessions:dG9rZW4y"
      }
    end
  end
end
