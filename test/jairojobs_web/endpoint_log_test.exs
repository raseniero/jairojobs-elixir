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

    # spec 005 — "Search words are not stored and are not written to logs." The words
    # are part of the page's address, so this follows a real search all the way: the
    # request for the address, the live connection, a search typed into the form, and a
    # type chosen. The log is captured at its most detailed level, where the parameter
    # lines are written; the file's usual level would not show them at all.
    test "REQ-005-4: searched words never appear in the log", %{conn: conn} do
      import Phoenix.LiveViewTest

      region = Jairojobs.RegionsFixtures.region_fixture(name: "Davao City")
      Logger.configure(level: :debug)

      log =
        capture_log(fn ->
          get(conn, "/jobs/#{region.slug}?search=zanzibarista&type=part-time")
          get(conn, "/?search=zanzibarista")

          {:ok, view, _html} = live(conn, "/jobs/#{region.slug}?search=zanzibarista")

          view |> form("#search-form", %{search: "quetzalcoatl"}) |> render_submit()

          view
          |> form("#search-form", %{search: "xylophonist", type: "part-time"})
          |> render_change(%{"_target" => ["type"]})

          view |> element("#region-choice-all") |> render_click()
        end)

      # The requests and the live events were logged, parameters and all…
      assert log =~ "GET /jobs/davao-city"
      assert log =~ "Parameters:"
      assert log =~ "[FILTERED]"
      assert log =~ "part-time"

      # …and none of the words is anywhere in it.
      for word <- ["zanzibarista", "quetzalcoatl", "xylophonist"] do
        refute log =~ word
      end
    end
  end
end
