defmodule MijnverbruikWeb.ChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MijnverbruikWeb.Charts

  test "draws return below the zero line only when there is return" do
    bars = [%{label: "10:00", up: 500, down: 0}, %{label: "11:00", up: 200, down: 300}]
    html = render_component(&Charts.bars/1, id: "c", title: "T", unit: :kwh, bars: bars)
    doc = LazyHTML.from_fragment(html)

    assert doc |> LazyHTML.query("rect.fill-success") |> Enum.count() == 1
    assert doc |> LazyHTML.query("[data-bar]") |> Enum.count() == 2
    assert html =~ "11:00: 0.20 kWh used, 0.30 kWh returned"

    html =
      render_component(&Charts.bars/1,
        id: "c",
        title: "T",
        unit: :m3,
        bars: [%{label: "a", up: 1}]
      )

    refute html =~ "fill-success"
  end

  test "labels round gridlines and spaces x-axis labels" do
    bars = for h <- 0..23, do: %{label: "#{h}:00", up: 1000 + h * 10}
    html = render_component(&Charts.bars/1, id: "c", title: "T", unit: :kwh, bars: bars)

    assert html =~ "0.50 kWh"
    assert html =~ "1.00 kWh"
    labels = html |> LazyHTML.from_fragment() |> LazyHTML.query("[style^='left:']")

    assert Enum.map(labels, &LazyHTML.text/1) |> Enum.map(&String.trim/1) ==
             ["0:00", "4:00", "8:00", "12:00", "16:00", "20:00"]
  end

  describe "power/1" do
    defp power(points) do
      html = render_component(&Charts.power/1, id: "c", title: "T", points: points)
      {html, LazyHTML.from_fragment(html)}
    end

    test "breaks the line where data is missing and reads out each point" do
      point = &%{label: &1, up: &2, down: &3}

      {html, doc} =
        power([
          point.("10:00", 500, 0),
          point.("10:05", 0, 300),
          point.("10:10", nil, nil),
          point.("10:15", 200, 0)
        ])

      # A line and an area per run, once in each colour.
      assert doc |> LazyHTML.query("path") |> Enum.count() == 8
      assert doc |> LazyHTML.query("[data-bar]") |> Enum.count() == 4
      assert html =~ "10:05: 0 W used, 300 W returned"
      assert html =~ "10:10: no data"
      assert html =~ "max 500 W · returned max 300 W"
      assert html =~ "Returned"
    end

    test "labels a day of 5-minute points without crowding the axis" do
      points = for i <- 0..287, do: %{label: "t#{i}", up: i, down: 0}
      {html, doc} = power(points)

      assert doc |> LazyHTML.query("[style^='left:']") |> Enum.count() == 6
      refute html =~ "Returned"
    end

    test "draws nothing without data" do
      {_html, doc} = power([%{label: "10:00", up: nil, down: nil}])

      assert doc |> LazyHTML.query("path") |> Enum.count() == 0
    end
  end
end
