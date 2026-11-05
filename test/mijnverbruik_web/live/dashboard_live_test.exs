defmodule MijnverbruikWeb.DashboardLiveTest do
  use MijnverbruikWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mijnverbruik.TelegramFixtures

  test "shows live power once a telegram arrives", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Waiting for the meter"
    assert has_element?(view, "#recent")
    assert has_element?(view, "#hours-gas")

    {:ok, telegram} = DSMR.parse(raw_telegram())
    send(view.pid, {:telegram, telegram})

    assert view |> element("#power") |> render() =~ "2027"
    assert has_element?(view, "#trend path")
    refute has_element?(view, "#meter-status")
  end

  test "charts electricity per 5 minutes and gas per hour", %{conn: conn} do
    now = System.os_time(:second)
    minute = now - rem(now, 300) - 600

    for {at, wh, gas} <- [{minute, 1000, 500}, {minute + 300, 1100, 525}] do
      Mijnverbruik.Repo.insert!(%Mijnverbruik.Readings.Reading{
        minute: at,
        equipment_id: "E1",
        delivered_t1_wh: wh,
        delivered_t2_wh: 0,
        returned_t1_wh: 0,
        returned_t2_wh: 0,
        gas_l: gas
      })
    end

    {:ok, view, _html} = live(conn, ~p"/")

    label =
      minute
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!("Europe/Amsterdam")
      |> Calendar.strftime("%H:%M")

    assert has_element?(view, ~s(#recent-chart [data-bar="#{label}: 1200 W"]))
    assert view |> element("#recent-chart") |> render() |> count_bars() == 288
    assert view |> element("#hours-gas-chart") |> render() |> count_bars() == 24
  end

  defp count_bars(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-bar]") |> Enum.count()

  test "marks live values stale when telegrams stop or the meter goes offline", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    {:ok, telegram} = DSMR.parse(raw_telegram())
    send(view.pid, {:telegram, telegram})

    send(view.pid, {:tick, System.os_time(:second) + 11})
    assert view |> element("#meter-status") |> render() =~ "No data from the meter"

    send(view.pid, :meter_offline)
    assert view |> element("#meter-status") |> render() =~ "Meter offline"

    send(view.pid, {:telegram, telegram})
    refute has_element?(view, "#meter-status")
  end

  test "shows phase load against the main fuse and warns near its limit", %{conn: conn} do
    {:ok, _} = Mijnverbruik.Settings.update(%{main_fuse_a: 25})
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, telegram} = DSMR.parse(raw_telegram())
    send(view.pid, {:telegram, telegram})
    assert has_element?(view, "#phase-2 [role=meter][aria-valuemax='25'][aria-valuenow='6']")
    refute has_element?(view, "[id^=fuse-warning]")

    telegram = put_in(telegram.phase_power_current_l2.value, 24)
    send(view.pid, {:telegram, telegram})
    assert has_element?(view, "#fuse-warning-2")
  end

  test "shows today's prices with a dynamic tariff", %{conn: conn} do
    tz = "Europe/Amsterdam"
    today = DateTime.now!(tz) |> DateTime.to_date()

    {:ok, _} =
      Mijnverbruik.Tariffs.create_tariff(%{
        valid_from: today,
        contract: "dynamic",
        electricity_surcharge: "0.15",
        electricity_return: "0.15",
        gas_contract: "dynamic",
        gas: "0.70",
        fixed_per_month: "0"
      })

    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#prices")
    refute has_element?(view, "#gas-price")

    now = System.os_time(:second)
    hour = now - rem(now, 3600)

    Mijnverbruik.Repo.insert_all(Mijnverbruik.Prices.MarketPrice, [
      %{hour: hour, commodity: :electricity, price: 0.10},
      %{hour: hour, commodity: :gas, price: 1.0}
    ])

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#prices")
    assert view |> element("#price-now") |> render() =~ "€0.27"
    assert view |> element("#gas-price") |> render() =~ "€1.91/m³"
  end
end
