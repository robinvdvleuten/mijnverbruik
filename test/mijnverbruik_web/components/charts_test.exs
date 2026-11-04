defmodule MijnverbruikWeb.ChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MijnverbruikWeb.Charts

  test "draws return below the zero line only when there is return" do
    bars = [%{label: "10:00", up: 500, down: 0}, %{label: "11:00", up: 200, down: 300}]
    html = render_component(&Charts.bars/1, id: "c", title: "T", unit: :kwh, bars: bars)
    doc = LazyHTML.from_fragment(html)

    assert doc |> LazyHTML.query("rect.fill-success") |> Enum.count() == 1
    assert doc |> LazyHTML.query("line") |> Enum.count() == 1

    html =
      render_component(&Charts.bars/1,
        id: "c",
        title: "T",
        unit: :m3,
        bars: [%{label: "a", up: 1}]
      )

    refute html =~ "fill-success"
  end
end
