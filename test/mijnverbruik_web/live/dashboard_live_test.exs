defmodule MijnverbruikWeb.DashboardLiveTest do
  use MijnverbruikWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mijnverbruik.TelegramFixtures

  test "shows live power once a telegram arrives", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Waiting for the meter"
    assert has_element?(view, "#hours")
    assert has_element?(view, "#days")

    {:ok, telegram} = DSMR.parse(raw_telegram())
    send(view.pid, {:telegram, telegram})

    assert view |> element("#power") |> render() =~ "2027"
  end
end
