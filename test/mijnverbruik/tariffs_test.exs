defmodule Mijnverbruik.TariffsTest do
  use Mijnverbruik.DataCase, async: true

  alias Mijnverbruik.{Readings, Tariffs}
  alias Mijnverbruik.Readings.Reading

  @attrs %{
    electricity_low: "0.20",
    electricity_normal: "0.30",
    electricity_return: "0.10",
    gas: "1.50",
    fixed_per_month: "-36.50"
  }

  defp tariff!(valid_from, attrs \\ %{}) do
    {:ok, tariff} =
      @attrs |> Map.merge(attrs) |> Map.put(:valid_from, valid_from) |> Tariffs.create_tariff()

    tariff
  end

  test "energy cost prices each register and subtracts return" do
    tariff = tariff!(~D[2026-01-01])
    usage = %{delivered_t1_wh: 1000, delivered_t2_wh: 2000, returned_wh: 500, gas_l: 2000}

    assert_in_delta Tariffs.energy_cost(tariff, usage), 0.2 + 0.6 - 0.05 + 3.0, 1.0e-9
    assert_in_delta Tariffs.fixed_per_day(tariff), -1.2, 1.0e-9
  end

  test "valid_on picks the latest tariff that has started" do
    old = tariff!(~D[2026-01-01])
    new = tariff!(~D[2026-07-01])
    tariffs = Tariffs.list_tariffs()

    assert Tariffs.valid_on(tariffs, ~D[2025-12-31]) == nil
    assert Tariffs.valid_on(tariffs, ~D[2026-06-30]).id == old.id
    assert Tariffs.valid_on(tariffs, ~D[2026-07-01]).id == new.id
  end

  test "rejects two tariffs starting on the same date and negative prices" do
    tariff!(~D[2026-01-01])
    assert {:error, cs} = Tariffs.create_tariff(Map.put(@attrs, :valid_from, ~D[2026-01-01]))
    assert %{valid_from: [_]} = errors_on(cs)

    attrs = %{@attrs | gas: "-1"} |> Map.put(:valid_from, ~D[2026-02-01])
    assert %{gas: [_]} = attrs |> Tariffs.create_tariff() |> elem(1) |> errors_on()
  end

  test "daily costs use the tariff of each day, nil before the first tariff" do
    tz = "Europe/Amsterdam"
    today = DateTime.now!(tz) |> DateTime.to_date()
    tariff!(today, %{fixed_per_month: "0"})
    start = today |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()

    for {minute, t2} <- [{start, 0}, {start + 60, 2000}] do
      Repo.insert!(%Reading{
        minute: minute,
        equipment_id: "E1",
        delivered_t1_wh: 0,
        delivered_t2_wh: t2,
        returned_t1_wh: 0,
        returned_t2_wh: 0
      })
    end

    assert [%{cost: nil}, %{cost: cost, delivered_t2_wh: 2000}] = Readings.daily(2, tz)
    assert_in_delta cost, 0.6, 1.0e-9
  end
end
