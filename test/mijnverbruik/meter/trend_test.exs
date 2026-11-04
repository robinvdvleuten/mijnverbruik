defmodule Mijnverbruik.Meter.TrendTest do
  use ExUnit.Case, async: false

  import Mijnverbruik.TelegramFixtures

  alias Mijnverbruik.Meter
  alias Mijnverbruik.Meter.Trend

  test "keeps the latest live values and recent power samples" do
    pid = start_supervised!({Trend, name: :trend_test})
    {:ok, telegram} = DSMR.parse(raw_telegram())

    Meter.broadcast(telegram)
    _ = :sys.get_state(pid)

    assert %{latest: {%{power_w: 2027}, at}, samples: [{at, 2027}]} = Trend.snapshot(:trend_test)
  end

  test "is empty when not running" do
    assert Trend.snapshot(:not_running) == %{latest: nil, samples: []}
  end

  test "prune drops samples outside the window" do
    now = 1_000
    samples = [{now - 300, 1}, {now - 299, 2}, {now, 3}]
    assert Trend.prune(samples, now) == [{now - 299, 2}, {now, 3}]
  end
end
