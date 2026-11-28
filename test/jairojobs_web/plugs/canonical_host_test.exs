defmodule JairojobsWeb.Plugs.CanonicalHostTest do
  # Changes application config, so not async.
  use JairojobsWeb.ConnCase, async: false

  alias JairojobsWeb.Plugs.CanonicalHost

  setup do
    previous = Application.get_env(:jairojobs, :redirect_hosts)
    on_exit(fn -> Application.put_env(:jairojobs, :redirect_hosts, previous) end)
    Application.put_env(:jairojobs, :redirect_hosts, ["www.jairojobs.com", "jairojobs.fly.dev"])
    :ok
  end

  defp canonical_host, do: JairojobsWeb.Endpoint.config(:url)[:host]

  test "a listed host is sent to the same page on the configured host, query kept" do
    conn =
      build_conn(:get, "/jobs/cebu?type=part-time&search=cook")
      |> Map.put(:host, "www.jairojobs.com")
      |> CanonicalHost.call([])

    assert conn.halted
    assert conn.status == 301

    assert get_resp_header(conn, "location") ==
             ["https://#{canonical_host()}/jobs/cebu?type=part-time&search=cook"]
  end

  test "a listed host with no query is sent on without a stray question mark" do
    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "jairojobs.fly.dev")
      |> CanonicalHost.call([])

    assert get_resp_header(conn, "location") == ["https://#{canonical_host()}/"]
  end

  test "the configured host and hosts not listed are left alone" do
    for host <- [canonical_host(), "elsewhere.example"] do
      conn = build_conn(:get, "/") |> Map.put(:host, host) |> CanonicalHost.call([])
      refute conn.halted
      assert conn.status == nil
    end
  end

  test "with no hosts listed, every request is left alone" do
    Application.put_env(:jairojobs, :redirect_hosts, [])

    conn =
      build_conn(:get, "/")
      |> Map.put(:host, "www.jairojobs.com")
      |> CanonicalHost.call([])

    refute conn.halted
  end

  test "the endpoint sends a listed host on before serving anything" do
    conn = build_conn(:get, "/robots.txt") |> Map.put(:host, "www.jairojobs.com")
    conn = JairojobsWeb.Endpoint.call(conn, [])

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["https://#{canonical_host()}/robots.txt"]
  end
end
