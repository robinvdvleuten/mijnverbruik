defmodule Mijnverbruik.PricesTest do
  use Mijnverbruik.DataCase, async: false

  alias Mijnverbruik.{Prices, Readings, Tariffs}
  alias Mijnverbruik.Prices.Fetcher
  alias Mijnverbruik.Readings.Reading

  @tz "Europe/Amsterdam"

  defp stub_prices(date) do
    Req.Test.stub(Prices, fn conn ->
      send(self(), {:params, conn.query_params})
      start = date |> DateTime.new!(~T[00:00:00], @tz) |> DateTime.to_unix()

      prices =
        for i <- 0..23 do
          at = DateTime.from_unix!(start + i * 3600)
          %{"readingDate" => DateTime.to_iso8601(at), "price" => i / 100}
        end

      Req.Test.json(conn, %{"Prices" => prices})
    end)
  end

  test "fetch stores the hourly prices of a local day" do
    stub_prices(~D[2026-11-04])

    assert {:ok, 24} = Prices.fetch(~D[2026-11-04], @tz)
    assert_received {:params, %{"fromDate" => "2026-11-03T23:00:00Z", "interval" => "4"}}

    start = DateTime.new!(~D[2026-11-04], ~T[00:00:00], @tz) |> DateTime.to_unix()
    assert %{^start => +0.0} = Prices.between(start, start + 86_400)

    assert Prices.missing_dates(~D[2026-11-03], ~D[2026-11-05], @tz) == [
             ~D[2026-11-03],
             ~D[2026-11-05]
           ]
  end

  test "fetch reports API errors" do
    Req.Test.stub(Prices, &Plug.Conn.send_resp(&1, 503, "down"))
    assert {:error, {:status, 503}} = Prices.fetch(~D[2026-11-04], @tz)
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
    assert Tariffs.energy_cost(tariff, usage, nil) == nil
    assert_in_delta Tariffs.energy_cost(tariff, usage, 0.10), (0.121 + 0.15) * 1, 1.0e-9

    midnight = today |> DateTime.new!(~T[00:00:00], @tz) |> DateTime.to_unix()
    Repo.insert_all(Prices.MarketPrice, [%{hour: midnight, price: 0.10}])

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
