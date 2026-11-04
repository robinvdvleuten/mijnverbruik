defmodule Mijnverbruik.Prices do
  @moduledoc """
  Day-ahead electricity market prices for the Netherlands, fetched from the
  public EnergyZero API (no account needed) and stored per UTC hour.
  """
  import Ecto.Query

  require Logger

  alias Mijnverbruik.Prices.MarketPrice
  alias Mijnverbruik.Repo

  @url "https://api.energyzero.nl/v1/energyprices"
  @vat 0.21

  @doc "The VAT rate added to market prices."
  def vat, do: @vat

  @doc "Prices for UTC hours from `from` (inclusive) to `to` (exclusive) as `%{hour => price}`."
  def between(from, to) when is_integer(from) and is_integer(to) do
    Repo.all(
      from p in MarketPrice,
        where: p.hour >= ^from and p.hour < ^to,
        select: {p.hour, p.price}
    )
    |> Map.new()
  end

  @doc "The average price over UTC hours from `from` to `to`, or nil without prices."
  def average(from, to) do
    Repo.one(from p in MarketPrice, where: p.hour >= ^from and p.hour < ^to, select: avg(p.price))
  end

  @doc """
  Fetches and stores the prices of local `date`. Returns `{:ok, count}`;
  count is 0 when the prices are not published yet (around 13:00 the day
  before).
  """
  def fetch(%Date{} = date, tz) do
    {from, to} = day_bounds(date, tz)

    params = [
      fromDate: from |> DateTime.from_unix!() |> DateTime.to_iso8601(),
      tillDate: (to - 1) |> DateTime.from_unix!() |> DateTime.to_iso8601(),
      interval: 4,
      usageType: 1,
      inclBtw: false
    ]

    options =
      Keyword.merge(
        [url: @url, params: params, retry: :transient],
        Application.get_env(:mijnverbruik, :prices_req_options, [])
      )

    with {:ok, %Req.Response{status: 200, body: %{"Prices" => prices}}} <- Req.request(options) do
      rows =
        for %{"readingDate" => at, "price" => price} <- prices,
            {:ok, at, _} = DateTime.from_iso8601(at),
            do: %{hour: DateTime.to_unix(at), price: price / 1}

      Repo.insert_all(MarketPrice, rows, on_conflict: :replace_all, conflict_target: :hour)
      {:ok, length(rows)}
    else
      {:ok, response} -> {:error, {:status, response.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Local dates from `first` to `last` that lack prices for some of their hours."
  def missing_dates(%Date{} = first, %Date{} = last, tz) do
    {from, _} = day_bounds(first, tz)
    {_, to} = day_bounds(last, tz)
    stored = between(from, to)

    Enum.filter(Date.range(first, last), fn date ->
      {start, stop} = day_bounds(date, tz)
      Enum.any?(start..(stop - 3600)//3600, &(not Map.has_key?(stored, &1)))
    end)
  end

  defp day_bounds(date, tz) do
    start = date |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    stop = date |> Date.add(1) |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    {start, stop}
  end
end
