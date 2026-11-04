defmodule Mijnverbruik.Prices do
  @moduledoc """
  Day-ahead market prices for electricity (per hour) and gas (per gas day,
  06:00 to 06:00 local time) in the Netherlands, fetched from the public
  EnergyZero API (no account needed) and stored per UTC hour.
  """
  import Ecto.Query

  alias Mijnverbruik.Prices.MarketPrice
  alias Mijnverbruik.Repo

  @url "https://public.api.energyzero.nl/public/v1/prices"
  @vat 0.21
  @commodities [:electricity, :gas]
  @requests [
    electricity: [energyType: "ENERGY_TYPE_ELECTRICITY", interval: "INTERVAL_HOUR"],
    gas: [energyType: "ENERGY_TYPE_GAS", interval: "INTERVAL_DAY"]
  ]

  @doc "The VAT rate added to market prices."
  def vat, do: @vat

  @doc """
  `commodity` prices for UTC hours from `from` (inclusive) to `to`
  (exclusive) as `%{hour => price}`.
  """
  def between(from, to, commodity \\ :electricity) when is_integer(from) and is_integer(to) do
    Repo.all(
      from p in MarketPrice,
        where: p.commodity == ^commodity and p.hour >= ^from and p.hour < ^to,
        select: {p.hour, p.price}
    )
    |> Map.new()
  end

  @doc "The average electricity price over UTC hours from `from` to `to`, or nil without prices."
  def average(from, to) do
    Repo.one(
      from p in MarketPrice,
        where: p.commodity == :electricity and p.hour >= ^from and p.hour < ^to,
        select: avg(p.price)
    )
  end

  @doc """
  Fetches and stores the electricity and gas prices around local `date`.
  Returns `{:ok, count}` with the number of hours stored; prices for
  tomorrow appear in the afternoon.
  """
  def fetch(%Date{} = date) do
    Enum.reduce_while(@commodities, {:ok, 0}, fn commodity, {:ok, total} ->
      case fetch_commodity(commodity, date) do
        {:ok, count} -> {:cont, {:ok, total + count}}
        error -> {:halt, error}
      end
    end)
  end

  defp fetch_commodity(commodity, date) do
    params = [date: Calendar.strftime(date, "%d-%m-%Y")] ++ @requests[commodity]

    options =
      Keyword.merge(
        [url: @url, params: params, retry: :transient],
        Application.get_env(:mijnverbruik, :prices_req_options, [])
      )

    case Req.request(options) do
      {:ok, %Req.Response{status: 200, body: %{"base" => blocks}}} ->
        rows =
          for %{"start" => start, "end" => stop, "price" => %{"value" => price}} <- blocks,
              hour <- hours(start, stop),
              do: %{hour: hour, commodity: commodity, price: to_float(price)}

        Repo.insert_all(MarketPrice, rows,
          on_conflict: {:replace, [:price]},
          conflict_target: [:hour, :commodity]
        )

        {:ok, length(rows)}

      # No prices published for this date yet.
      {:ok, %Req.Response{status: 404}} ->
        {:ok, 0}

      {:ok, response} ->
        {:error, {:status, response.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The UTC hours a price block covers; `base` is the market price excluding VAT.
  defp hours(start, stop) do
    {:ok, start, _} = DateTime.from_iso8601(start)
    {:ok, stop, _} = DateTime.from_iso8601(stop)
    start = DateTime.to_unix(start)
    Enum.to_list(start..(DateTime.to_unix(stop) - 1)//3600)
  end

  defp to_float(value) when is_binary(value), do: value |> Float.parse() |> elem(0)
  defp to_float(value), do: value / 1

  @doc """
  Local dates from `first` to `last` that lack an electricity or gas price
  for some of their hours.
  """
  def missing_dates(%Date{} = first, %Date{} = last, tz) do
    {from, _} = day_bounds(first, tz)
    {_, to} = day_bounds(last, tz)
    stored = Enum.map(@commodities, &between(from, to, &1))

    Enum.filter(Date.range(first, last), fn date ->
      {start, stop} = day_bounds(date, tz)

      for prices <- stored, hour <- start..(stop - 3600)//3600, reduce: false do
        missing -> missing or not Map.has_key?(prices, hour)
      end
    end)
  end

  defp day_bounds(date, tz) do
    start = date |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    stop = date |> Date.add(1) |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    {start, stop}
  end
end
