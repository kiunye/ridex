defmodule Ridex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RidexWeb.Telemetry,
      Ridex.Repo,
      {DNSCluster, query: Application.get_env(:ridex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ridex.PubSub},
      # Start Phoenix Presence
      Ridex.Presence,
      # Start the location cleanup job
      Ridex.LocationCleanupJob,
      # Start the Finch HTTP client for sending emails
      {Finch, name: Ridex.Finch},
      # Start a worker by calling: Ridex.Worker.start_link(arg)
      # {Ridex.Worker, arg},
      # Start to serve requests, typically the last entry
      RidexWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ridex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RidexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
