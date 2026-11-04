defmodule Mijnverbruik.InsightsTest do
  use Mijnverbruik.DataCase, async: false

  alias Mijnverbruik.Insights
  alias Mijnverbruik.Readings.Reading

  @tz "Europe/Amsterdam"
  @now DateTime.new!(~D[2026-11-04], ~T[12:00:00], @tz) |> DateTime.shift_zone!("Etc/UTC")

  # Writes one reading at the start of each hour of each night from 8 nights
  # ago to last night. `use_w` and `gas_l` give each hour's usage.
  defp nights(use_w, gas_l \\ fn _date, _hour -> 0 end) do
    dates = Date.range(~D[2026-10-27], ~D[2026-11-04])

    for date <- dates, hour <- 0..6, reduce: {0, 0} do
      {wh, l} ->
        at = DateTime.new!(date, Time.new!(hour, 0, 0), @tz)

        Repo.insert!(%Reading{
          minute: DateTime.to_unix(at),
          equipment_id: "E1",
          delivered_t1_wh: wh,
          delivered_t2_wh: 0,
          returned_t1_wh: 0,
          returned_t2_wh: 0,
          gas_l: l
        })

        # Hour 6 only closes the night; daytime use is ignored.
        if hour == 6,
          do: {wh + 5000, l + 1000},
          else: {wh + use_w.(date, hour), l + gas_l.(date, hour)}
    end
  end

  test "standby is the lowest night hour over the last 7 nights" do
    nights(fn date, hour -> if date == ~D[2026-10-30] and hour == 3, do: 90, else: 150 end)

    assert %{standby_w: 90, warnings: []} = Insights.summary(@tz, @now)
  end

  test "warns when last night's standby is well above usual" do
    nights(fn date, _hour -> if date == ~D[2026-11-04], do: 260, else: 150 end)

    assert %{warnings: [{:standby_high, 260, 150}]} = Insights.summary(@tz, @now)
  end

  test "warns about steady gas flow at night, not about heating cycles" do
    nights(fn _, _ -> 150 end, fn date, hour ->
      if date == ~D[2026-11-04] and hour in 1..4, do: 30, else: 0
    end)

    assert %{warnings: [{:gas_at_night, 120}]} = Insights.summary(@tz, @now)

    Repo.delete_all(Reading)

    nights(fn _, _ -> 150 end, fn date, hour ->
      if date == ~D[2026-11-04] and hour in [1, 3], do: 200, else: 0
    end)

    assert %{warnings: []} = Insights.summary(@tz, @now)
  end

  test "is empty without data" do
    assert %{standby_w: nil, standby_cost_year: nil, warnings: []} = Insights.summary(@tz, @now)
  end
end
