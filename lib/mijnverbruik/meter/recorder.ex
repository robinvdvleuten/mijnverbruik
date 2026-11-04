defmodule Mijnverbruik.Meter.Recorder do
  @moduledoc """
  Stores the first telegram of every minute as a `Mijnverbruik.Readings.Reading`
  and broadcasts `{:recorded, minute}` to `Mijnverbruik.Readings.subscribe/0` subscribers.
  """
  use GenServer

  require Logger

  alias Mijnverbruik.{Meter, Readings}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])

  @impl true
  def init(_opts) do
    :ok = Meter.subscribe()
    {:ok, %{last_minute: nil}}
  end

  @impl true
  def handle_info({:telegram, telegram}, state) do
    with {:ok, reading} <- Readings.from_telegram(telegram),
         true <- state.last_minute == nil or reading.minute > state.last_minute,
         {:ok, _} <- Readings.record(reading) do
      Readings.broadcast_recorded(reading.minute)
      {:noreply, %{state | last_minute: reading.minute}}
    else
      :error ->
        Logger.warning("Telegram lacks timestamp or registers; not recorded")
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end
end
