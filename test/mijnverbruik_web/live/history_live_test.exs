defmodule MijnverbruikWeb.HistoryLiveTest do
  use MijnverbruikWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mijnverbruik.Readings.Reading
  alias Mijnverbruik.Repo

  @tz "Europe/Amsterdam"

  defp insert(%DateTime{} = at, delivered_wh) do
    Repo.insert!(%Reading{
      minute: DateTime.to_unix(at),
      equipment_id: "E1",
      delivered_t1_wh: delivered_wh,
      delivered_t2_wh: 0,
      returned_t1_wh: 0,
      returned_t2_wh: 0
    })
  end

  test "shows a past day and compares it with the day before", %{conn: conn} do
    insert(DateTime.new!(~D[2026-10-01], ~T[10:00:00], @tz), 0)
    insert(DateTime.new!(~D[2026-10-01], ~T[11:00:00], @tz), 1000)
    insert(DateTime.new!(~D[2026-10-02], ~T[10:00:00], @tz), 2000)
    insert(DateTime.new!(~D[2026-10-02], ~T[11:00:00], @tz), 3500)

    {:ok, view, _html} = live(conn, ~p"/history?period=day&date=2026-10-02")

    assert view |> element("#period-title") |> render() =~ "Vrijdag 2 oktober 2026"
    assert view |> element("#total-electricity") |> render() =~ "1,50"
    assert view |> element("#total-electricity") |> render() =~ "+50%"
    assert has_element?(view, "#history-electricity")
    assert has_element?(view, "#history-gas")

    # A past day has no "now" marker; each hour has a tooltip with the day before.
    tip =
      view
      |> element("#history-electricity-chart [data-bar]:nth-child(11)")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("data-tip")
      |> hd()
      |> Jason.decode!()

    assert tip["title"] == "10:00 – 11:00"
    assert ["Afname", "1,50 kWh", _] = hd(tip["rows"])
    assert ["Dag ervoor", "1,00 kWh", _] = List.last(tip["rows"])
  end

  test "switches periods and steps back and forth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history?period=week&date=2026-10-07")
    assert view |> element("#period-title") |> render() =~ "Week 41 · 5 – 11 oktober 2026"

    view |> element("#previous-period") |> render_click()
    assert_patch(view, ~p"/history?#{[date: "2026-09-28", period: "week"]}")
    assert view |> element("#period-title") |> render() =~ "Week 40"

    view |> element("#period-month") |> render_click()
    assert view |> element("#period-title") |> render() =~ "September 2026"

    view |> element("#period-year") |> render_click()
    assert view |> element("#period-title") |> render() =~ "2026"
    refute has_element?(view, "#next-period")
  end

  test "falls back to today for a bad period or date", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history?period=decade&date=nope")
    assert has_element?(view, "#period-day[aria-current=page]")
    refute has_element?(view, "#next-period")
  end
end
