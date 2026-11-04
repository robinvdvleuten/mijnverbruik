defmodule Mijnverbruik.Readings do
  @moduledoc """
  Stores per-minute meter register snapshots and derives usage from them.

  Usage for a period is always the difference between two cumulative register
  values. Deltas are only taken between readings of the same meter
  (`equipment_id`), because a replaced meter starts its registers over, and a
  negative delta is never reported.
  """

  alias Mijnverbruik.Readings.Reading
  alias Mijnverbruik.Repo

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

  @doc """
  Usage per UTC hour from `from` (inclusive) onwards.

  Each hour runs from its first reading to the first reading of the next hour
  with data, so energy used during a gap is attributed to the hour before it.
  The latest hour runs to its last reading. Returns maps sorted by hour with
  `:hour` (unix seconds), `:delivered_wh`, `:returned_wh` and `:gas_l`.
  """
  def hourly(%DateTime{} = from) do
    sql = """
    WITH buckets AS (
      SELECT minute / 3600 * 3600 AS hour, equipment_id,
             MIN(delivered_t1_wh + delivered_t2_wh) AS d_start,
             MAX(delivered_t1_wh + delivered_t2_wh) AS d_end,
             MIN(returned_t1_wh + returned_t2_wh) AS r_start,
             MAX(returned_t1_wh + returned_t2_wh) AS r_end,
             MIN(gas_l) AS g_start,
             MAX(gas_l) AS g_end
      FROM readings
      WHERE minute >= ?1
      GROUP BY hour, equipment_id
    )
    SELECT hour,
           MAX(LEAD(d_start, 1, d_end) OVER w - d_start, 0),
           MAX(LEAD(r_start, 1, r_end) OVER w - r_start, 0),
           MAX(LEAD(g_start, 1, g_end) OVER w - g_start, 0)
    FROM buckets
    WINDOW w AS (PARTITION BY equipment_id ORDER BY hour)
    """

    %{rows: rows} = Repo.query!(sql, [DateTime.to_unix(from)])

    rows
    |> Enum.map(fn [hour, d, r, g] ->
      %{hour: hour, delivered_wh: d, returned_wh: r, gas_l: g || 0}
    end)
    |> Enum.group_by(& &1.hour)
    |> Enum.map(fn {hour, parts} ->
      %{
        hour: hour,
        delivered_wh: sum(parts, :delivered_wh),
        returned_wh: sum(parts, :returned_wh),
        gas_l: sum(parts, :gas_l)
      }
    end)
    |> Enum.sort_by(& &1.hour)
  end

  @doc """
  Usage per local day for the last `days` days including today.
  """
  def daily(days, tz \\ timezone()) when days > 0 do
    today = DateTime.now!(tz) |> DateTime.to_date()
    first = Date.add(today, 1 - days)

    totals =
      first
      |> local_midnight(tz)
      |> hourly()
      |> Enum.group_by(fn %{hour: hour} ->
        hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      end)

    for date <- Date.range(first, today) do
      parts = Map.get(totals, date, [])

      %{
        date: date,
        delivered_wh: sum(parts, :delivered_wh),
        returned_wh: sum(parts, :returned_wh),
        gas_l: sum(parts, :gas_l)
      }
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

  defp sum(parts, key), do: parts |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()

  defp timezone, do: Application.fetch_env!(:mijnverbruik, :timezone)
end
