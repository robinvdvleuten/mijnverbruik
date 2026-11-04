defmodule Mijnverbruik.PricesTest do
  use Mijnverbruik.DataCase, async: false

  alias Mijnverbruik.{Prices, Readings, Tariffs}
  alias Mijnverbruik.Prices.Fetcher
  alias Mijnverbruik.Readings.Reading

  @tz "Europe/Amsterdam"

  # Mimics EnergyZero: hourly electricity blocks for the local day, and gas
  # in one block per gas day from 06:00 local time.
  defp stub_prices(date) do
    Req.Test.stub(Prices, fn conn ->
      send(self(), {:params, conn.query_params})
      start = date |> DateTime.new!(~T[00:00:00], @tz) |> DateTime.to_unix()

      blocks =
        case conn.query_params["energyType"] do
          "ENERGY_TYPE_ELECTRICITY" ->
            for i <- 0..23, do: block(start + i * 3600, 3600, Float.to_string(i / 100))

          "ENERGY_TYPE_GAS" ->
            [block(start - 18 * 3600, 86_400, "0.90"), block(start + 6 * 3600, 86_400, "0.95")]
        end

      Req.Test.json(conn, %{"base" => blocks, "all_in" => []})
    end)
  end

  defp block(start, length, price) do
    %{
      "start" => start |> DateTime.from_unix!() |> DateTime.to_iso8601(),
      "end" => (start + length) |> DateTime.from_unix!() |> DateTime.to_iso8601(),
      "price" => %{"value" => price}
    }
  end

  test "fetch stores hourly electricity and per gas day prices" do
    stub_prices(~D[2026-11-04])

    assert {:ok, 72} = Prices.fetch(~D[2026-11-04])

    assert_received {:params,
                     %{"date" => "04-11-2026", "energyType" => "ENERGY_TYPE_ELECTRICITY"}}

    assert_received {:params, %{"interval" => "INTERVAL_DAY", "energyType" => "ENERGY_TYPE_GAS"}}

    start = DateTime.new!(~D[2026-11-04], ~T[00:00:00], @tz) |> DateTime.to_unix()
    assert %{^start => +0.0} = Prices.between(start, start + 86_400)

    gas = Prices.between(start, start + 86_400, :gas)
    assert gas[start + 5 * 3600] == 0.90
    assert gas[start + 6 * 3600] == 0.95

    assert Prices.missing_dates(~D[2026-11-03], ~D[2026-11-05], @tz) == [
             ~D[2026-11-03],
             ~D[2026-11-05]
           ]
  end

  test "fetch treats unpublished prices as none yet" do
    Req.Test.stub(Prices, &Plug.Conn.send_resp(&1, 404, ~s({"message":"not found"})))
    assert {:ok, 0} = Prices.fetch(~D[2026-11-04])
  end

  test "fetch reports API errors" do
    Req.Test.stub(Prices, &Plug.Conn.send_resp(&1, 503, "down"))
    assert {:error, {:status, 503}} = Prices.fetch(~D[2026-11-04])
  end

  test "dynamic costs use the hourly market price plus VAT and surcharge" do
    today = DateTime.now!(@tz) |> DateTime.to_date()

    {:ok, tariff} =
      Tariffs.create_tariff(%{
        valid_from: today,
        contract: "dynamic",
        electricity_surcharge: "0.15",
        electricity_return: "0.15",
        gas: "1.40",
        fixed_per_month: "0"
      })

    usage = %{delivered_wh: 2000, returned_wh: 1000, gas_l: 0}
    assert Tariffs.energy_cost(tariff, usage, %{}) == nil
    assert_in_delta Tariffs.energy_cost(tariff, usage, %{electricity: 0.10}), 0.271, 1.0e-9

    midnight = today |> DateTime.new!(~T[00:00:00], @tz) |> DateTime.to_unix()

    Repo.insert_all(Prices.MarketPrice, [
      %{hour: midnight, commodity: :electricity, price: 0.10}
    ])

    for {minute, wh} <- [{midnight, 0}, {midnight + 60, 1000}, {midnight + 3600, 1000}] do
      Repo.insert!(%Reading{
        minute: minute,
        equipment_id: "E1",
        delivered_t1_wh: wh,
        delivered_t2_wh: 0,
        returned_t1_wh: 0,
        returned_t2_wh: 0
      })
    end

    assert [%{cost: cost}] = Readings.days(today, today, @tz)
    assert_in_delta cost, 0.271, 1.0e-9
  end

  test "dynamic gas uses the gas day's market price plus VAT and surcharge" do
    {:ok, tariff} =
      Tariffs.create_tariff(%{
        valid_from: ~D[2026-01-01],
        contract: "fixed",
        electricity_low: "0.20",
        electricity_normal: "0.30",
        electricity_return: "0.10",
        gas_contract: "dynamic",
        gas: "0.70",
        fixed_per_month: "0"
      })

    usage = %{delivered_t1_wh: 0, delivered_t2_wh: 0, returned_wh: 0, gas_l: 2000}
    assert Tariffs.energy_cost(tariff, usage, %{}) == nil
    assert_in_delta Tariffs.energy_cost(tariff, usage, %{gas: 1.0}), 2 * (1.21 + 0.70), 1.0e-9
    assert Tariffs.energy_cost(tariff, %{usage | gas_l: 0}, %{}) == 0.0
  end

  test "the fetcher only fetches for dynamic tariffs, newest missing first" do
    today = DateTime.now!(@tz) |> DateTime.to_date()
    assert Fetcher.dates_to_fetch(@tz, Tariffs.list_tariffs()) == []

    {:ok, _} =
      Tariffs.create_tariff(%{
        valid_from: Date.add(today, -2),
        contract: "dynamic",
        electricity_surcharge: "0.15",
        electricity_return: "0",
        gas: "1.40",
        fixed_per_month: "0"
      })

    assert Fetcher.dates_to_fetch(@tz, Tariffs.list_tariffs()) ==
             [Date.add(today, 1), today, Date.add(today, -1), Date.add(today, -2)]
  end
end
