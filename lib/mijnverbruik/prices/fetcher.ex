defmodule Mijnverbruik.Prices.Fetcher do
  @moduledoc """
  Keeps market prices complete while any tariff is dynamic: every hour it
  fetches the days since the first dynamic tariff (at most a year back) that
  lack prices, up to tomorrow, newest first and at most 31 days per run.
  """
  use GenServer

  require Logger

  alias Mijnverbruik.{Prices, Tariffs}

  @interval :timer.hours(1)
  @max_days_per_run 31

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Fetches missing prices now instead of waiting for the next run."
  def refresh do
    if pid = GenServer.whereis(__MODULE__), do: send(pid, :fetch)
    :ok
  end

  @impl true
  def init(_opts) do
    send(self(), :fetch)
    {:ok, nil}
  end

  @impl true
  def handle_info(:fetch, timer) do
    if timer, do: Process.cancel_timer(timer)
    tz = Application.fetch_env!(:mijnverbruik, :timezone)

    tz
    |> dates_to_fetch(Tariffs.list_tariffs())
    |> Enum.each(fn date ->
      case Prices.fetch(date, tz) do
        {:ok, _count} ->
          :ok

        {:error, reason} ->
          Logger.warning("Fetching prices for #{date} failed: #{inspect(reason)}")
      end
    end)

    {:noreply, Process.send_after(self(), :fetch, @interval)}
  end

  @doc """
  Local dates to fetch prices for, newest first, given all `tariffs`.
  """
  def dates_to_fetch(tz, tariffs) do
    case for(%{contract: :dynamic, valid_from: from} <- tariffs, do: from) do
      [] ->
        []

      starts ->
        today = tz |> DateTime.now!() |> DateTime.to_date()
        first = Enum.max([Enum.min(starts, Date), Date.add(today, -365)], Date)

        first
        |> Prices.missing_dates(Date.add(today, 1), tz)
        |> Enum.reverse()
        |> Enum.take(@max_days_per_run)
    end
  end
end
