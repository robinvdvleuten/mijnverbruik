defmodule MijnverbruikWeb.DashboardLiveTest do
  use MijnverbruikWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mijnverbruik.TelegramFixtures

  test "shows live power once a telegram arrives", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Waiting for the meter"
    assert has_element?(view, "#hours")
    assert has_element?(view, "#days")
    assert has_element?(view, "#hours-gas")
    assert has_element?(view, "#days-gas")

    {:ok, telegram} = DSMR.parse(raw_telegram())
    send(view.pid, {:telegram, telegram})

    assert view |> element("#power") |> render() =~ "2027"
    refute has_element?(view, "#meter-status")
  end

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
end
