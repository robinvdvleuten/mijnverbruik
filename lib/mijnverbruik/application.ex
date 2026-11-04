defmodule Mijnverbruik.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        MijnverbruikWeb.Telemetry,
        Mijnverbruik.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:mijnverbruik, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:mijnverbruik, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Mijnverbruik.PubSub}
      ] ++
        meter_children() ++
        price_children() ++
        [
          # Start to serve requests, typically the last entry
          MijnverbruikWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mijnverbruik.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MijnverbruikWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Only read and record when a meter is configured, so tests and dev without
  # a meter run without connection errors.
  defp meter_children do
    meter = Application.get_env(:mijnverbruik, :meter, [])

    case meter[:host] do
      nil ->
        []

      host ->
        [
          Mijnverbruik.Meter.Recorder,
          Mijnverbruik.Meter.Trend,
          {Mijnverbruik.Meter.Reader, host: host, port: meter[:port]}
        ]
    end
  end

  # Market prices are fetched over the network, so tests leave this off.
  defp price_children do
    if Application.get_env(:mijnverbruik, :fetch_prices, true),
      do: [Mijnverbruik.Prices.Fetcher],
      else: []
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
