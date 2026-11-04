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
             "must be greater than or equal to 0"

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
    assert html =~ "on top of market price"
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
end
