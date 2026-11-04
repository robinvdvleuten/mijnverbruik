defmodule MijnverbruikWeb.SettingsLiveTest do
  use MijnverbruikWeb.ConnCase, async: true

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
end
