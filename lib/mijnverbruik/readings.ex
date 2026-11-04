defmodule Mijnverbruik.Readings do
  @moduledoc """
  Stores per-minute meter register snapshots and derives usage from them.

  Usage for a period is always the difference between two cumulative register
  values. Deltas are only taken between readings of the same meter
  (`equipment_id`), because a replaced meter starts its registers over, and a
  negative delta is never reported.
  """

  alias Mijnverbruik.Readings.Reading
  alias Mijnverbruik.{Repo, Tariffs}

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
  Usage per UTC hour from `from` (inclusive) onwards.

  Each hour runs from its first reading to the first reading of the next hour
  with data, so energy used during a gap is attributed to the hour before it.
  The latest hour runs to its last reading. Returns maps sorted by hour with
  `:hour` (unix seconds), `:delivered_wh` split into `:delivered_t1_wh` (low
  tariff) and `:delivered_t2_wh` (normal tariff), `:returned_wh` and `:gas_l`.
  """
  def hourly(%DateTime{} = from) do
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
      WHERE minute >= ?1
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

    %{rows: rows} = Repo.query!(sql, [DateTime.to_unix(from)])

    rows
    |> Enum.map(fn [hour, d1, d2, r, g] ->
      %{hour: hour, delivered_t1_wh: d1, delivered_t2_wh: d2, returned_wh: r, gas_l: g || 0}
    end)
    |> Enum.group_by(& &1.hour)
    |> Enum.map(fn {hour, parts} -> parts |> total() |> Map.put(:hour, hour) end)
    |> Enum.sort_by(& &1.hour)
  end

  @doc """
  Usage and costs per local day for the last `days` days including today.

  `:cost` is the energy cost of the day plus its fixed costs, using the
  tariff valid on that day, or nil when no tariff applies.
  """
  def daily(days, tz \\ timezone()) when days > 0 do
    today = DateTime.now!(tz) |> DateTime.to_date()
    first = Date.add(today, 1 - days)
    tariffs = Tariffs.list_tariffs()

    totals =
      first
      |> local_midnight(tz)
      |> hourly()
      |> Enum.group_by(fn %{hour: hour} ->
        hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      end)

    for date <- Date.range(first, today) do
      usage = totals |> Map.get(date, []) |> total()

      cost =
        case Tariffs.valid_on(tariffs, date) do
          nil -> nil
          tariff -> Tariffs.energy_cost(tariff, usage) + Tariffs.fixed_per_day(tariff)
        end

      usage |> Map.put(:date, date) |> Map.put(:cost, cost)
    end
  end

  @doc """
  Usage since local midnight.
  """
  def today(tz \\ timezone()) do
    [today] = daily(1, tz)
    today
  end

  defp local_midnight(date, tz), do: DateTime.new!(date, ~T[00:00:00], tz)

  @usage_keys [:delivered_t1_wh, :delivered_t2_wh, :returned_wh, :gas_l]

  defp total(parts) do
    usage = Map.new(@usage_keys, fn key -> {key, parts |> Enum.map(& &1[key]) |> Enum.sum()} end)
    Map.put(usage, :delivered_wh, usage.delivered_t1_wh + usage.delivered_t2_wh)
  end

  defp timezone, do: Application.fetch_env!(:mijnverbruik, :timezone)
end
