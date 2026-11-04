defmodule JairojobsWeb.PageControllerTest do
  use JairojobsWeb.ConnCase

  test "REQ-001-1: public home page renders without login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
    refute get_session(conn, :user_token)
  end
end
