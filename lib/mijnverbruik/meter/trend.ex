defmodule Mijnverbruik.Meter.Trend do
  @moduledoc """
  Keeps the latest live values and the net power of the last 5 minutes in
  memory, so a newly opened dashboard shows them straight away. Nothing is
  written to the database.
  """
  use GenServer

  alias Mijnverbruik.Meter

  @window 300

  def window, do: @window

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Returns `%{latest: {live, unix_seconds} | nil, samples: [{unix_seconds, power_w}]}`
  with samples oldest first, or an empty snapshot when no meter is configured.
  """
  def snapshot(server \\ __MODULE__) do
    if GenServer.whereis(server),
      do: GenServer.call(server, :snapshot),
      else: %{latest: nil, samples: []}
  end

  @doc "Drops samples older than the window, relative to `now`."
  def prune(samples, now), do: Enum.drop_while(samples, fn {t, _} -> t <= now - @window end)

  @impl true
  def init(_opts) do
    :ok = Meter.subscribe()
    {:ok, %{latest: nil, samples: :queue.new()}}
  end

  @impl true
  def handle_info({:telegram, telegram}, state) do
    now = System.os_time(:second)
    live = Meter.live(telegram)
    samples = :queue.in({now, live.power_w}, state.samples)
    {:noreply, %{state | latest: {live, now}, samples: drop_old(samples, now)}}
  end

  def handle_info(:meter_offline, state), do: {:noreply, state}

  @impl true
  def handle_call(:snapshot, _from, state) do
    samples = state.samples |> :queue.to_list() |> prune(System.os_time(:second))
    {:reply, %{latest: state.latest, samples: samples}, state}
  end

  defp drop_old(queue, now) do
    case :queue.peek(queue) do
      {:value, {t, _}} when t <= now - @window -> queue |> :queue.drop() |> drop_old(now)
      _ -> queue
    end
  end
end
