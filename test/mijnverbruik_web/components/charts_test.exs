defmodule MijnverbruikWeb.ChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MijnverbruikWeb.Charts

  defp bars(opts) do
    html = render_component(&Charts.bars/1, Keyword.merge([id: "c", label: "T"], opts))
    {html, LazyHTML.from_fragment(html)}
  end

  describe "bars/1" do
    test "draws return below the zero line only when there is return" do
      {html, doc} =
        bars(
          unit: :kwh,
          bars: [%{label: "10:00", up: 500, down: 0}, %{label: "11:00", up: 200, down: 300}]
        )

      assert doc |> LazyHTML.query("rect.fill-return") |> Enum.count() == 1
      assert doc |> LazyHTML.query("[data-bar]") |> Enum.count() == 2
      assert html =~ "11:00: 0,20 kWh afgenomen, 0,30 kWh terug"

      {_html, doc} = bars(unit: :m3, bars: [%{label: "a", up: 1}])
      assert doc |> LazyHTML.query("rect.fill-return") |> Enum.count() == 0
    end

    test "reads out bars without data and spaces up to six x-axis labels" do
      bars = for h <- 0..23, do: %{label: "#{h}:00", up: if(h == 5, do: nil, else: 1000)}
      {html, doc} = bars(unit: :kwh, bars: bars)

      assert html =~ "5:00: geen data"

      labels = doc |> LazyHTML.query("figure > div > span") |> Enum.map(&LazyHTML.text/1)
      assert labels == ["0:00", "4:00", "8:00", "12:00", "16:00", "20:00"]
    end

    test "uses given ticks and tones price bars" do
      bars = [
        %{label: "00:00", up: 0.2, down: 0, tone: :past},
        %{label: "01:00", up: 0.3, down: 0, tone: :now},
        %{label: "02:00", up: 0.1, down: 0, tone: :cheap}
      ]

      {html, doc} = bars(unit: :eur_kwh, bars: bars, ticks: ["00", "nu"])

      assert doc |> LazyHTML.query("rect.fill-ink") |> Enum.count() == 1
      assert doc |> LazyHTML.query("rect.fill-return") |> Enum.count() == 1
      assert html =~ "01:00: € 0,300/kWh"

      assert doc |> LazyHTML.query("figure > div > span") |> Enum.map(&LazyHTML.text/1) == [
               "00",
               "nu"
             ]
    end
  end

  describe "trend/1" do
    defp trend(samples, opts \\ []) do
      html =
        render_component(
          &Charts.trend/1,
          Keyword.merge([id: "t", samples: samples, now: 1000, window: 300], opts)
        )

      LazyHTML.from_fragment(html)
    end

    test "breaks the line where samples are more than 5 seconds apart" do
      doc = trend([{800, 500}, {801, 520}, {900, 480}, {901, 470}])

      # A line and an area per run, once in each colour.
      assert doc |> LazyHTML.query("path") |> Enum.count() == 8
    end

    test "turns grey when stale" do
      doc = trend([{990, 500}, {991, 520}], stale: true)

      assert doc |> LazyHTML.query("path.stroke-stale") |> Enum.count() == 2
      assert doc |> LazyHTML.query("path.stroke-use") |> Enum.count() == 0
    end
  end
end
