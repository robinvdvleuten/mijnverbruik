defmodule Mijnverbruik.ReadingsTest do
  use Mijnverbruik.DataCase, async: false

  import Mijnverbruik.TelegramFixtures

  alias Mijnverbruik.Readings
  alias Mijnverbruik.Readings.Reading

  @hour 1_767_258_000

  defp insert(minute, delivered_wh, opts \\ []) do
    Repo.insert!(%Reading{
      minute: minute,
      equipment_id: Keyword.get(opts, :equipment_id, "E1"),
      delivered_t1_wh: delivered_wh,
      delivered_t2_wh: 0,
      returned_t1_wh: 0,
      returned_t2_wh: 0,
      gas_l: Keyword.get(opts, :gas_l)
    })
  end

  describe "from_telegram/1" do
    test "converts registers to integer Wh and litres at the minute" do
      {:ok, telegram} = DSMR.parse(raw_telegram())

      assert {:ok, reading} = Readings.from_telegram(telegram)
      # 2016-11-13 20:57:57 winter time = 19:57:57 UTC
      assert reading.minute == DateTime.to_unix(~U[2016-11-13 19:57:00Z])
      assert reading.delivered_t1_wh == 1_581_123
      assert reading.delivered_t2_wh == 1_435_706
      assert reading.gas_l == 981_443
      assert reading.equipment_id == "3960221976967177082151037881335713"
    end

    test "rejects telegrams without registers" do
      assert Readings.from_telegram(%DSMR.Telegram{header: "X", checksum: ""}) == :error
    end
  end

  describe "record/1" do
    test "keeps the first reading of a minute" do
      {:ok, reading} = Readings.from_telegram(telegram(~N[2026-01-01 10:00:05], 1.0))
      {:ok, later} = Readings.from_telegram(telegram(~N[2026-01-01 10:00:40], 1.5))

      assert {:ok, _} = Readings.record(reading)
      assert {:ok, _} = Readings.record(later)
      assert [%Reading{delivered_t1_wh: 1000}] = Repo.all(Reading)
    end
  end

  describe "hourly/1" do
    test "attributes energy used during a gap to the hour before it" do
      insert(@hour, 1000)
      insert(@hour + 1800, 1200)
      # collector down for almost three hours
      insert(@hour + 3 * 3600 + 600, 2000)
      insert(@hour + 3 * 3600 + 1200, 2100)

      assert [
               %{hour: @hour, delivered_wh: 1000},
               %{hour: h2, delivered_wh: 100}
             ] = Readings.hourly(DateTime.from_unix!(@hour))

      assert h2 == @hour + 3 * 3600
    end

    test "never subtracts across a meter swap" do
      insert(@hour, 5000)
      insert(@hour + 600, 5100)
      insert(@hour + 3600, 10, equipment_id: "E2")
      insert(@hour + 3600 + 600, 50, equipment_id: "E2")

      assert [%{delivered_wh: 100}, %{delivered_wh: 40}] =
               Readings.hourly(DateTime.from_unix!(@hour))
    end

    test "sums gas deltas" do
      insert(@hour, 0, gas_l: 100)
      insert(@hour + 300, 0, gas_l: 130)

      assert [%{gas_l: 30}] = Readings.hourly(DateTime.from_unix!(@hour))
    end
  end

  describe "gas_flow/1" do
    defp gas_rows(start, values, opts \\ []) do
      values
      |> Enum.with_index()
      |> Enum.each(fn {gas, i} -> insert(start + i * 60, 0, Keyword.put(opts, :gas_l, gas)) end)
    end

    test "uses the interval between the last two changes of the total" do
      # Total changes at minute 2 (+40 l) and minute 7 (+62 l).
      gas_rows(@hour, [1000, 1000, 1040, 1040, 1040, 1040, 1040, 1102, 1102])

      assert Readings.gas_flow(@hour + 8 * 60) == div(62 * 3600, 300)
    end

    test "is zero when the total has not changed for 10 minutes" do
      gas_rows(@hour, List.duplicate(1000, 11))
      assert Readings.gas_flow(@hour + 10 * 60) == 0

      Repo.delete_all(Reading)
      gas_rows(@hour, [1000, 1010, 1010, 1010, 1010, 1010, 1020] ++ List.duplicate(1020, 10))
      assert Readings.gas_flow(@hour + 16 * 60) == 0
    end

    test "is nil until two changes are seen, or when readings are stale" do
      assert Readings.gas_flow(@hour) == nil

      gas_rows(@hour, [1000, 1000, 1010, 1010])
      assert Readings.gas_flow(@hour + 3 * 60) == nil

      gas_rows(@hour + 4 * 60, [1010, 1010, 1010, 1020])
      assert Readings.gas_flow(@hour + 7 * 60 + 3600) == nil
    end

    test "ignores readings of a replaced meter" do
      gas_rows(@hour, [9000, 9100], equipment_id: "OLD")
      gas_rows(@hour + 120, [10, 20, 20, 20, 20, 20, 30])

      assert Readings.gas_flow(@hour + 120 + 6 * 60) == div(10 * 3600, 300)
    end
  end

  describe "daily/2 and today/1" do
    test "sums usage from local midnight" do
      tz = "Europe/Amsterdam"
      midnight = DateTime.new!(Date.utc_today() |> Date.add(-1), ~T[00:00:00], tz)
      start = DateTime.to_unix(midnight)

      insert(start, 1000)
      insert(start + 86_400, 4000)
      insert(start + 86_400 + 60, 4500)

      assert [%{delivered_wh: yesterday}, %{delivered_wh: 500} = today] = Readings.daily(2, tz)
      assert yesterday == 3000
      assert Readings.today(tz) == today
    end
  end
end
