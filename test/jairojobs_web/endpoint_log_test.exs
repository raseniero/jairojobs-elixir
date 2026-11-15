defmodule JairojobsWeb.EndpointLogTest do
  # Not async: raises the global Logger level for the duration of each test, because the
  # test environment normally silences the request log (level :warning).
  use JairojobsWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias JairojobsWeb.Endpoint

  setup do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
  end

  describe "log_level/1" do
    test "REQ-001: requests whose address carries a sign-in or email-change token are not logged" do
      assert Endpoint.log_level(%Plug.Conn{path_info: ["users", "log-in", "secret"]}) == false

      assert Endpoint.log_level(%Plug.Conn{
               path_info: ["users", "settings", "confirm-email", "secret"]
             }) == false
    end

    test "every other request is logged at info" do
      for path <- [
            [],
            ["users", "log-in"],
            ["users", "settings"],
            ["users", "register"],
            ["my", "listings", "0190-uuid"],
            ["admin", "regions"]
          ] do
        assert Endpoint.log_level(%Plug.Conn{path_info: path}) == :info
      end
    end
  end

  describe "request log" do
    test "REQ-001: a sign-in token never appears in the request log", %{conn: conn} do
      token = "s3cret-magic-link-token"

      log = capture_log(fn -> get(conn, ~p"/users/log-in/#{token}") end)

      refute log =~ token
      refute log =~ "GET /users/log-in/"
    end

    test "REQ-001: an email-change token never appears in the request log", %{conn: conn} do
      token = "s3cret-change-email-token"

      log = capture_log(fn -> get(conn, ~p"/users/settings/confirm-email/#{token}") end)

      refute log =~ token
    end

    test "other requests are still logged", %{conn: conn} do
      log = capture_log(fn -> get(conn, ~p"/users/log-in") end)

      assert log =~ "GET /users/log-in"
      assert log =~ "Sent 200"
    end
  end
end
