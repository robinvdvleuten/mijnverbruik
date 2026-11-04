defmodule Mijnverbruik.Readings do
  @moduledoc """
  Stores per-minute meter register snapshots and derives usage from them.

  Usage for a period is always the difference between two cumulative register
  values. Deltas are only taken between readings of the same meter
  (`equipment_id`), because a replaced meter starts its registers over, and a
  negative delta is never reported.
  """

  alias Mijnverbruik.Readings.Reading
  alias Mijnverbruik.{Prices, Repo, Tariffs}

  @topic "readings"

  def subscribe, do: Phoenix.PubSub.subscribe(Mijnverbruik.PubSub, @topic)

  def broadcast_recorded(minute),
    do: Phoenix.PubSub.broadcast(Mijnverbruik.PubSub, @topic, {:recorded, minute})

  @doc """
  Builds a reading from a parsed telegram.

  Returns `:error` when the telegram lacks a timestamp with DST marker or one
  of the electricity registers.
  """
  def from_telegram(%DSMR.Telegram{} = telegram) do
    with %DSMR.Timestamp{} = ts <- telegram.measured_at,
         {:ok, measured_at} <- DSMR.Timestamp.to_datetime(ts),
         equipment_id when is_binary(equipment_id) <- telegram.equipment_id,
         {:ok, d1} <- milli(telegram.electricity_delivered_1),
         {:ok, d2} <- milli(telegram.electricity_delivered_2),
         {:ok, r1} <- milli(telegram.electricity_returned_1),
         {:ok, r2} <- milli(telegram.electricity_returned_2) do
      unix = DateTime.to_unix(measured_at)

      {:ok,
       %Reading{
         minute: unix - rem(unix, 60),
         equipment_id: equipment_id,
         delivered_t1_wh: d1,
         delivered_t2_wh: d2,
         returned_t1_wh: r1,
         returned_t2_wh: r2,
         gas_l: gas_litres(telegram.mbus_devices)
       }}
    else
      _ -> :error
    end
  end

  # kWh -> Wh and m3 -> l: registers have three decimals, so rounding is exact.
  defp milli(%DSMR.Measurement{value: value}) when is_number(value),
    do: {:ok, round(value * 1000)}

  defp milli(_), do: :error

  defp gas_litres(devices) do
    Enum.find_value(devices, fn
      %DSMR.MBusDevice{device_type: "003", last_reading_value: m} ->
        case milli(m) do
          {:ok, litres} -> litres
          :error -> nil
        end

      _ ->
        nil
    end)
  end

  @doc """
  Inserts a reading unless one already exists for that minute.
  """
  def record(%Reading{} = reading) do
    Repo.insert(reading, on_conflict: :nothing, conflict_target: :minute)
  end

  # Gas meters report a new total every 5 minutes (DSMR 5). Ten minutes
  # without a change means no gas is being used.
  @gas_idle 600
  @gas_lookback 1200

  @doc """
  Gas flow in litres per hour over the meter's latest update interval.

  Meters do not report instantaneous gas flow, only a total that changes every
  5 minutes. The flow is the difference between the last two changes of that
  total divided by the time between them, or 0 when the total has not changed
  for 10 minutes. Returns `nil` when recent readings are missing or do not yet
  contain two changes.
  """
  def gas_flow(now \\ System.os_time(:second)) do
    import Ecto.Query

    rows =
      Repo.all(
        from r in Reading,
          where: not is_nil(r.gas_l) and r.minute >= ^(now - @gas_lookback),
          order_by: [asc: r.minute],
          select: {r.minute, r.gas_l, r.equipment_id}
      )

    with {latest_minute, _gas, equipment_id} <- List.last(rows),
         true <- now - latest_minute <= @gas_idle do
      changes =
        rows
        |> Enum.filter(&(elem(&1, 2) == equipment_id))
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [{_, prev, _}, {_, gas, _}] -> gas != prev end)
        |> Enum.map(fn [_, {minute, gas, _}] -> {minute, gas} end)

      case Enum.take(changes, -2) do
        [{_, _}, {last_change, _}] when latest_minute - last_change >= @gas_idle -> 0
        [{m1, g1}, {m2, g2}] when g2 > g1 -> div((g2 - g1) * 3600, m2 - m1)
        _ when changes == [] and latest_minute - elem(hd(rows), 0) >= @gas_idle -> 0
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  @doc """
  Usage per UTC hour from `from` (inclusive) until `to` (exclusive, or now).

  Each hour runs from its first reading to the first reading of the next hour
  with data, so energy used during a gap is attributed to the hour before it.
  The latest hour runs to its last reading. Returns maps sorted by hour with
  `:hour` (unix seconds), `:delivered_wh` split into `:delivered_t1_wh` (low
  tariff) and `:delivered_t2_wh` (normal tariff), `:returned_wh` and `:gas_l`.
  """
  def hourly(%DateTime{} = from, to \\ nil) do
    # The hour after `to` is read too, since the last hour ends at its first reading.
    stop = if to, do: DateTime.to_unix(to), else: :infinity
    until = if to, do: DateTime.to_unix(to) + 3600, else: 9_999_999_999

    sql = """
    WITH buckets AS (
      SELECT minute / 3600 * 3600 AS hour, equipment_id,
             MIN(delivered_t1_wh) AS d1_start,
             MAX(delivered_t1_wh) AS d1_end,
             MIN(delivered_t2_wh) AS d2_start,
             MAX(delivered_t2_wh) AS d2_end,
             MIN(returned_t1_wh + returned_t2_wh) AS r_start,
             MAX(returned_t1_wh + returned_t2_wh) AS r_end,
             MIN(gas_l) AS g_start,
             MAX(gas_l) AS g_end
      FROM readings
      WHERE minute >= ?1 AND minute < ?2
      GROUP BY hour, equipment_id
    )
    SELECT hour,
           MAX(LEAD(d1_start, 1, d1_end) OVER w - d1_start, 0),
           MAX(LEAD(d2_start, 1, d2_end) OVER w - d2_start, 0),
           MAX(LEAD(r_start, 1, r_end) OVER w - r_start, 0),
           MAX(LEAD(g_start, 1, g_end) OVER w - g_start, 0)
    FROM buckets
    WINDOW w AS (PARTITION BY equipment_id ORDER BY hour)
    """

    %{rows: rows} = Repo.query!(sql, [DateTime.to_unix(from), until])

    rows
    |> Enum.map(fn [hour, d1, d2, r, g] ->
      %{hour: hour, delivered_t1_wh: d1, delivered_t2_wh: d2, returned_wh: r, gas_l: g || 0}
    end)
    |> Enum.filter(&(&1.hour < stop))
    |> Enum.group_by(& &1.hour)
    |> Enum.map(fn {hour, parts} -> parts |> total() |> Map.put(:hour, hour) end)
    |> Enum.sort_by(& &1.hour)
  end

  @doc """
  Usage and costs for every local hour of `date`, including hours without
  data and hours still to come (23 or 25 hours when the clocks change).

  `:cost` is the hour's energy cost plus its share of the fixed costs, using
  the tariff valid on `date`. It is nil when no tariff applies, the hour has
  not started, or a dynamic tariff lacks the hour's market price; the current
  hour gets the fixed costs elapsed so far.
  """
  def hours(%Date{} = date, tz \\ timezone()) do
    calendar_hours(date, Date.add(date, 1), tz)
  end

  @doc """
  Usage and costs per local day from `first` to `last`, inclusive. A day's
  `:cost` is the sum of its hour costs (see `hours/2`), or nil when none has
  one.
  """
  def days(%Date{} = first, %Date{} = last, tz \\ timezone()) do
    by_date = first |> calendar_hours(Date.add(last, 1), tz) |> Enum.group_by(& &1.date)

    for date <- Date.range(first, last) do
      by_date |> Map.get(date, []) |> total() |> Map.put(:date, date)
    end
  end

  @doc """
  Usage and costs per month of `year`; `:month` is the first day of the month.
  """
  def months(year, tz \\ timezone()) do
    Date.new!(year, 1, 1)
    |> days(Date.new!(year, 12, 31), tz)
    |> Enum.chunk_by(& &1.date.month)
    |> Enum.map(fn [first | _] = days -> days |> total() |> Map.put(:month, first.date) end)
  end

  @doc """
  Usage and costs per local day for the last `days` days including today.
  """
  def daily(days, tz \\ timezone()) when days > 0 do
    today = local_today(tz)
    days(Date.add(today, 1 - days), today, tz)
  end

  @doc """
  Usage and costs since local midnight.
  """
  def today(tz \\ timezone()) do
    [today] = daily(1, tz)
    today
  end

  defp calendar_hours(%Date{} = first, %Date{} = stop, tz) do
    start = first |> local_midnight(tz) |> DateTime.to_unix()
    stop = stop |> local_midnight(tz) |> DateTime.to_unix()
    start = start - rem(start, 3600)
    now = System.os_time(:second)
    tariffs = Tariffs.list_tariffs()
    prices = Prices.between(start, stop)

    by_hour =
      start
      |> DateTime.from_unix!()
      |> hourly(DateTime.from_unix!(stop))
      |> Map.new(&{&1.hour, &1})

    for hour <- start..(stop - 3600)//3600 do
      date = hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      usage = Map.get_lazy(by_hour, hour, fn -> [] |> total() |> Map.put(:hour, hour) end)
      cost = hour_cost(Tariffs.valid_on(tariffs, date), usage, prices[hour], now - hour)
      Map.merge(usage, %{date: date, cost: cost})
    end
  end

  defp hour_cost(nil, _usage, _market, _elapsed), do: nil
  defp hour_cost(_tariff, _usage, _market, elapsed) when elapsed < 0, do: nil

  # A dynamic tariff without the hour's market price has no energy cost yet;
  # leave the whole hour out rather than show fixed costs only.
  defp hour_cost(tariff, usage, market, elapsed) do
    case Tariffs.energy_cost(tariff, usage, market) do
      nil -> nil
      energy -> energy + Tariffs.fixed_per_day(tariff) / 24 * min(elapsed, 3600) / 3600
    end
  end

  defp local_today(tz), do: tz |> DateTime.now!() |> DateTime.to_date()

  defp local_midnight(date, tz), do: DateTime.new!(date, ~T[00:00:00], tz)

  @usage_keys [:delivered_t1_wh, :delivered_t2_wh, :returned_wh, :gas_l]

  @doc """
  Sums usage maps. Costs sum when any part has one, so a period without any
  tariff stays nil.
  """
  def total(parts) do
    usage = Map.new(@usage_keys, fn key -> {key, parts |> Enum.map(& &1[key]) |> Enum.sum()} end)

    cost =
      case parts |> Enum.map(&Map.get(&1, :cost)) |> Enum.reject(&is_nil/1) do
        [] -> nil
        costs -> Enum.sum(costs)
      end

    Map.merge(usage, %{delivered_wh: usage.delivered_t1_wh + usage.delivered_t2_wh, cost: cost})
  end

  defp timezone, do: Application.fetch_env!(:mijnverbruik, :timezone)
end
