defmodule Mijnverbruik.Meter.RecorderTest do
  use Mijnverbruik.DataCase, async: false

  import Mijnverbruik.TelegramFixtures

  alias Mijnverbruik.{Meter, Readings}
  alias Mijnverbruik.Readings.Reading

  test "records the first telegram of each minute" do
    start_supervised!(Mijnverbruik.Meter.Recorder)
    Readings.subscribe()

    Meter.broadcast(telegram(~N[2026-01-01 10:00:05], 1.0))
    Meter.broadcast(telegram(~N[2026-01-01 10:00:40], 1.5))
    Meter.broadcast(telegram(~N[2026-01-01 10:01:02], 2.0))

    assert_receive {:recorded, first}
    assert_receive {:recorded, second}
    refute_receive {:recorded, _}
    assert second - first == 60

    assert [1000, 2000] =
             Reading |> order_by(:minute) |> select([r], r.delivered_t1_wh) |> Repo.all()
  end
end
