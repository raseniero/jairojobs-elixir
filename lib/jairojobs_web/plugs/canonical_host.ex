defmodule JairojobsWeb.Plugs.CanonicalHost do
  @moduledoc """
  Sends a request that arrives on another of the site's hosts to the same page
  on the one host the site is configured with (the endpoint's `url: [host: ...]`,
  `PHX_HOST` in production), with a permanent redirect (301).

  The hosts to send on are `config :jairojobs, :redirect_hosts` (in production,
  `REDIRECT_HOSTS`, comma-separated; for example `www.jairojobs.com,jairojobs.fly.dev`).
  The list is empty by default, which leaves every request alone.

  Without it a page opened on `www.` or on the fly.dev address would load but its
  LiveView would never connect: the socket accepts only the configured host
  (`check_origin`). It also leaves search engines one address per page.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if conn.host in Application.get_env(:jairojobs, :redirect_hosts, []) do
      conn
      |> put_resp_header("location", canonical_url(conn))
      |> send_resp(:moved_permanently, "")
      |> halt()
    else
      conn
    end
  end

  defp canonical_url(conn) do
    host = JairojobsWeb.Endpoint.config(:url)[:host]
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    "https://" <> host <> conn.request_path <> query
  end
end
