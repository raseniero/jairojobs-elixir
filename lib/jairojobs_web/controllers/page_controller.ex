defmodule JairojobsWeb.PageController do
  use JairojobsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
