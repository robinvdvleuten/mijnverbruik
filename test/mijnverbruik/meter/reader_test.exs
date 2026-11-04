defmodule Mijnverbruik.Meter.ReaderTest do
  use ExUnit.Case, async: false

  import Mijnverbruik.TelegramFixtures

  alias Mijnverbruik.Meter
  alias Mijnverbruik.Meter.Reader

  describe "split/1" do
    test "drops bytes before the first telegram and keeps a partial tail" do
      raw = raw_telegram()
      {head, tail} = String.split_at(raw, 100)

      assert Reader.split("garbage" <> raw <> raw <> head) == {[raw, raw], head}
      assert Reader.split(head <> tail) == {[raw], ""}
    end

    test "drops an oversized partial buffer" do
      assert Reader.split("/" <> String.duplicate("x", 20_000)) == {[], ""}
    end
  end

  test "broadcasts telegrams from the socket and reconnects after a disconnect" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    Meter.subscribe()

    start_supervised!({Reader, host: "127.0.0.1", port: port, backoff_ms: 10})

    {:ok, client} = :gen_tcp.accept(listen, 1_000)
    {head, tail} = String.split_at(raw_telegram(), 200)
    :ok = :gen_tcp.send(client, "noise" <> head)
    :ok = :gen_tcp.send(client, tail)
    assert_receive {:telegram, %DSMR.Telegram{version: "42"}}, 1_000

    :ok = :gen_tcp.close(client)
    assert_receive :meter_offline, 1_000
    {:ok, client} = :gen_tcp.accept(listen, 1_000)
    :ok = :gen_tcp.send(client, raw_telegram())
    assert_receive {:telegram, %DSMR.Telegram{}}, 1_000
  end
end
