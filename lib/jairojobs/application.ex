defmodule Jairojobs.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JairojobsWeb.Telemetry,
      Jairojobs.Repo,
      {DNSCluster, query: Application.get_env(:jairojobs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jairojobs.PubSub},
      # Start a worker by calling: Jairojobs.Worker.start_link(arg)
      # {Jairojobs.Worker, arg},
      # Start to serve requests, typically the last entry
      JairojobsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jairojobs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JairojobsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
