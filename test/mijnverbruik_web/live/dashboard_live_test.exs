defmodule MijnverbruikWeb.DashboardLiveTest do
  use MijnverbruikWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mijnverbruik.TelegramFixtures

  alias Mijnverbruik.Readings.Reading

  @tz "Europe/Amsterdam"

  defp telegram do
    {:ok, telegram} = DSMR.parse(raw_telegram())
    telegram
  end

  defp reading(minute, wh, gas_l, returned_wh \\ 0) do
    Mijnverbruik.Repo.insert!(%Reading{
      minute: minute,
      equipment_id: "E1",
      delivered_t1_wh: wh,
      delivered_t2_wh: 0,
      returned_t1_wh: returned_wh,
      returned_t2_wh: 0,
      gas_l: gas_l
    })
  end

  test "shows live power once a telegram arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert view |> element("#hero-title") |> render() =~ "Wachten op de meter"
    assert has_element?(view, "#electricity")
    assert has_element?(view, "#hours-gas")

    send(view.pid, {:telegram, telegram()})

    assert view |> element("#power") |> render() =~ "2.027"
    assert view |> element("#hero-title") |> render() =~ "Thuis gebruikt nu"
    assert has_element?(view, "#trend path")
    assert has_element?(view, "#meter-dot.bg-return")
    refute has_element?(view, "#meter-status")
  end

  test "says what returns to the grid and what comes from it on a day with return",
       %{conn: conn} do
    now = System.os_time(:second)
    minute = now - rem(now, 300) - 600
    reading(minute, 1000, 0, 0)
    reading(minute + 300, 1000, 0, 400)

    {:ok, view, _html} = live(conn, ~p"/")
    telegram = telegram()
    send(view.pid, {:telegram, telegram})
    assert view |> element("#hero-title") |> render() =~ "Nu uit het net"

    telegram =
      telegram
      |> put_in([Access.key(:electricity_currently_delivered), Access.key(:value)], 0.0)
      |> put_in([Access.key(:electricity_currently_returned), Access.key(:value)], 0.9)

    send(view.pid, {:telegram, telegram})
    assert view |> element("#hero-title") |> render() =~ "Nu teruggeleverd"
    assert view |> element("#power") |> render() =~ "900"
  end

  test "charts electricity per quarter hour and gas per hour", %{conn: conn} do
    now = System.os_time(:second)
    minute = now - rem(now, 300) - 600
    reading(minute, 1000, 500)
    reading(minute + 300, 1100, 525)

    {:ok, view, _html} = live(conn, ~p"/")

    label =
      (minute - rem(minute, 900))
      |> DateTime.from_unix!()
      |> DateTime.shift_zone!(@tz)
      |> Calendar.strftime("%H:%M")

    assert has_element?(view, ~s(#electricity-chart [data-bar^="#{label}: "][data-bar$=" W"]))
    assert view |> element("#electricity-chart") |> render() |> count_bars() == 96
    assert view |> element("#hours-gas-chart") |> render() |> count_bars() == 24
  end

  defp count_bars(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-bar]") |> Enum.count()

  test "greys out live values when telegrams stop and says so when the meter goes offline",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    send(view.pid, {:telegram, telegram()})

    send(view.pid, {:tick, System.os_time(:second) + 11})
    assert view |> element("#meter-status") |> render() =~ "Laatste meting om"
    assert has_element?(view, "#meter-dot.bg-warn")
    refute has_element?(view, "#offline-banner")

    send(view.pid, :meter_offline)
    assert view |> element("#offline-banner") |> render() =~ "Meter niet bereikbaar"

    send(view.pid, {:telegram, telegram()})
    refute has_element?(view, "#meter-status")
    refute has_element?(view, "#offline-banner")
  end

  test "shows phase load against the main fuse and warns near its limit", %{conn: conn} do
    {:ok, _} = Mijnverbruik.Settings.update(%{main_fuse_a: 25})
    {:ok, view, _html} = live(conn, ~p"/")

    telegram = telegram()
    send(view.pid, {:telegram, telegram})
    assert has_element?(view, "#phase-2 [role=meter][aria-valuemax='25'][aria-valuenow='6']")
    refute has_element?(view, "[id^=fuse-warning]")

    telegram = put_in(telegram.phase_power_current_l2.value, 24)
    send(view.pid, {:telegram, telegram})
    assert has_element?(view, "#fuse-warning-2")
  end

  test "shows today's prices with a dynamic tariff", %{conn: conn} do
    today = DateTime.now!(@tz) |> DateTime.to_date()

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
    assert view |> element("#prices-card") |> render() =~ "Nog geen marktprijzen"

    now = System.os_time(:second)
    hour = now - rem(now, 3600)

    Mijnverbruik.Repo.insert_all(Mijnverbruik.Prices.MarketPrice, [
      %{hour: hour, commodity: :electricity, price: 0.10},
      %{hour: hour, commodity: :gas, price: 1.0}
    ])

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#prices")
    assert view |> element("#price-now") |> render() =~ "€ 0,27"
    assert view |> element("#gas-price") |> render() =~ "€ 1,91/m³"
  end

  test "shows a fixed tariff, or asks for one when there is none", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert view |> element("#prices-card") |> render() =~ "Tarieven instellen"

    {:ok, _} =
      Mijnverbruik.Tariffs.create_tariff(%{
        valid_from: Date.add(Date.utc_today(), -1),
        contract: "fixed",
        electricity_normal: "0.27",
        electricity_low: "0.25",
        electricity_return: "0.09",
        gas_contract: "fixed",
        gas: "1.32",
        fixed_per_month: "0"
      })

    {:ok, view, _html} = live(conn, ~p"/")
    card = view |> element("#prices-card") |> render()
    assert card =~ "vast contract"
    assert card =~ "€ 0,27"
    assert card =~ "dal € 0,25"
    assert card =~ "€ 1,32"
  end

  test "tips about standby power that was high last night", %{conn: conn} do
    local = DateTime.now!(@tz)
    today = DateTime.to_date(local)
    last = if local.hour >= 6, do: today, else: Date.add(today, -1)

    # One reading at the start of each night hour, last night at 260 W and
    # the nights before at 150 W.
    for date <- Date.range(Date.add(last, -8), last), hour <- 0..6, reduce: 0 do
      wh ->
        at = DateTime.new!(date, Time.new!(hour, 0, 0), @tz) |> DateTime.to_unix()
        reading(at, wh, 0)
        if hour == 6, do: wh + 5000, else: wh + if(date == last, do: 260, else: 150)
    end

    {:ok, view, _html} = live(conn, ~p"/")
    assert view |> element("#tip") |> render() =~ "260 W"
    assert view |> element("#standby") |> render() =~ "150"
  end
end
