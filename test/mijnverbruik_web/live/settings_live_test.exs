defmodule MijnverbruikWeb.SettingsLiveTest do
  use MijnverbruikWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mijnverbruik.Tariffs

  @params %{
    "valid_from" => "2026-01-01",
    "electricity_normal" => "0.30",
    "electricity_low" => "0.28",
    "electricity_return" => "0.09",
    "gas" => "1.45",
    "fixed_per_month" => "38.20"
  }

  test "adds, edits and deletes a tariff", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert view |> form("#tariff-form", tariff: %{"gas" => "-1"}) |> render_change() =~
             "Moet minstens 0 zijn"

    view |> form("#tariff-form", tariff: @params) |> render_submit()
    [tariff] = Tariffs.list_tariffs()
    assert has_element?(view, "#tariffs-#{tariff.id}")

    view |> element("#tariffs-#{tariff.id} button[phx-click=edit]") |> render_click()
    view |> form("#tariff-form", tariff: %{"gas" => "1.50"}) |> render_submit()
    assert [%{gas: gas}] = Tariffs.list_tariffs()
    assert Decimal.equal?(gas, "1.50")

    view |> element("#tariffs-#{tariff.id} button[phx-click=delete]") |> render_click()
    refute has_element?(view, "#tariffs-#{tariff.id}")
    assert Tariffs.list_tariffs() == []
  end

  test "saves the main fuse", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    view |> form("#settings-form", setting: %{main_fuse_a: "35"}) |> render_submit()
    assert Mijnverbruik.Settings.get().main_fuse_a == 35
  end

  test "adds a dynamic tariff with only the fields it needs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html = view |> form("#tariff-form", tariff: %{"contract" => "dynamic"}) |> render_change()
    assert html =~ "bovenop marktprijs"
    refute has_element?(view, "#tariff_electricity_low")

    view
    |> form("#tariff-form",
      tariff: %{
        "contract" => "dynamic",
        "valid_from" => "2026-01-01",
        "electricity_surcharge" => "0.15",
        "electricity_return" => "0.15",
        "gas" => "1.40",
        "fixed_per_month" => "30"
      }
    )
    |> render_submit()

    assert [%{contract: :dynamic, electricity_low: nil}] = Tariffs.list_tariffs()
  end

  test "adds a tariff with a dynamic gas contract", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert view |> form("#tariff-form", tariff: %{"gas_contract" => "dynamic"}) |> render_change() =~
             "Gas, bovenop marktprijs"

    view
    |> form("#tariff-form", tariff: Map.put(@params, "gas_contract", "dynamic"))
    |> render_submit()

    assert [%{gas_contract: :dynamic, contract: :fixed} = tariff] = Tariffs.list_tariffs()
    assert view |> element("#tariffs-#{tariff.id}") |> render() =~ "gas markt + € 1,45 per m³"
  end

  test "shows what the meter says about itself once a telegram arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    assert view |> element("#meter") |> render() =~ "Wachten op de meter"

    {:ok, telegram} = DSMR.parse(Mijnverbruik.TelegramFixtures.raw_telegram())
    send(view.pid, {:telegram, telegram})

    meter = view |> element("#meter") |> render()
    assert meter =~ "Verbonden"
    assert meter =~ "Kaifa"
    assert meter =~ "DSMR 4.2"
    assert meter =~ "3-fase"

    send(view.pid, :meter_offline)
    assert view |> element("#meter") |> render() =~ "Niet verbonden"
  end

  test "marks the tariff that applies today as active", %{conn: conn} do
    {:ok, old} = Tariffs.create_tariff(@params)

    {:ok, current} =
      Tariffs.create_tariff(%{@params | "valid_from" => Date.to_iso8601(Date.utc_today())})

    {:ok, view, _html} = live(conn, ~p"/settings")
    assert view |> element("#tariffs-#{current.id}") |> render() =~ "actief"
    refute view |> element("#tariffs-#{old.id}") |> render() =~ "actief"
  end

  test "saves the location for sunrise and sunset", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert {:error, {:redirect, %{to: "/settings"}}} =
             view
             |> form("#location-form", location: %{latitude: "53.2", longitude: "6.57"})
             |> render_submit()

    assert Mijnverbruik.Settings.location() == %{latitude: 53.2, longitude: 6.57}

    html = conn |> get(~p"/settings") |> html_response(200)
    assert html =~ ~s(data-latitude="53.2")
  end

  test "refuses half a location", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    html =
      view
      |> form("#location-form", location: %{latitude: "53.2", longitude: ""})
      |> render_submit()

    assert html =~ "Vul dit in"
    assert Mijnverbruik.Settings.location() == %{latitude: 52.1, longitude: 5.18}
  end
end
