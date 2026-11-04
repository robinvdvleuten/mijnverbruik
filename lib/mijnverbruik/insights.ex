defmodule Mijnverbruik.Insights do
  @moduledoc """
  Standby power and warnings about unusual use, derived from the hourly usage
  of recent nights (00:00–06:00 local time), when nearly everything is off.
  """
  alias Mijnverbruik.{Prices, Readings, Tariffs}

  @nights 7
  @night_hours 0..5
  # A leak flows steadily; heating at night comes and goes.
  @gas_leak_hours 1..4
  @steady_ratio 0.5
  # Last night's standby is unusual when it is this much above the usual.
  @standby_factor 1.5
  @standby_margin_w 50

  @doc """
  Returns a map with:

    * `:standby_w` - the lowest hourly average power over the last 7 nights,
      or nil without data
    * `:standby_cost_year` - what that power costs per year at the average of
      today's low and normal tariff, or for a dynamic contract at the last
      30 days' average market price; nil without a tariff or prices
    * `:warnings` - a list of `{:standby_high, last_night_w, usual_w}` and
      `{:gas_at_night, litres}`
  """
  def summary(tz, now \\ DateTime.utc_now()) do
    nights = nights(tz, now)
    lows = Enum.map(nights, fn {_date, hours} -> lowest(hours) end)
    standby = lows |> Enum.take(-@nights) |> Enum.reject(&is_nil/1) |> Enum.min(fn -> nil end)

    %{
      standby_w: standby,
      standby_cost_year: standby && yearly_cost(standby, tz, now),
      warnings: standby_warning(lows) ++ gas_warning(nights)
    }
  end

  # The last 8 complete nights, oldest first, each as {date, %{hour => usage}}.
  defp nights(tz, now) do
    local = DateTime.shift_zone!(now, tz)

    last =
      if local.hour >= 6, do: DateTime.to_date(local), else: Date.add(DateTime.to_date(local), -1)

    first = Date.add(last, -@nights)

    by_hour =
      first
      |> DateTime.new!(~T[00:00:00], tz)
      |> Readings.hourly()
      |> Enum.map(fn usage ->
        at = usage.hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)
        {{DateTime.to_date(at), at.hour}, usage}
      end)
      |> Map.new()

    for date <- Date.range(first, last) do
      {date, for(h <- @night_hours, u = by_hour[{date, h}], into: %{}, do: {h, u})}
    end
  end

  # An hour's Wh equals its average power in W.
  defp lowest(hours) when map_size(hours) == 0, do: nil
  defp lowest(hours), do: hours |> Map.values() |> Enum.map(& &1.delivered_wh) |> Enum.min()

  defp standby_warning(lows) do
    {usual, [last_night]} = Enum.split(lows, -1)
    usual = usual |> Enum.reject(&is_nil/1) |> median()

    if last_night && usual && last_night > usual * @standby_factor &&
         last_night - usual >= @standby_margin_w,
       do: [{:standby_high, last_night, usual}],
       else: []
  end

  defp gas_warning(nights) do
    {_date, hours} = List.last(nights)
    gas = for h <- @gas_leak_hours, u = hours[h], do: u.gas_l

    if length(gas) == Enum.count(@gas_leak_hours) and Enum.min(gas) > 0 and
         Enum.min(gas) >= Enum.max(gas) * @steady_ratio,
       do: [{:gas_at_night, Enum.sum(gas)}],
       else: []
  end

  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end

  defp yearly_cost(watts, tz, now) do
    today = now |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    unix = DateTime.to_unix(now)

    with %{} = tariff <- Tariffs.valid_on(Tariffs.list_tariffs(), today),
         market = tariff.contract == :dynamic && Prices.average(unix - 30 * 86_400, unix),
         true <- market != nil do
      watts * 8760 / 1000 * Tariffs.kwh_price(tariff, market || nil)
    else
      _ -> nil
    end
  end
end
