defmodule MijnverbruikWeb.DashboardLive do
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.{Charts, Format}

  alias Mijnverbruik.{Meter, Readings}
  alias Mijnverbruik.Meter.Trend

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Meter.subscribe()
      Readings.subscribe()
      :timer.send_interval(1000, :tick)
    end

    %{latest: latest, samples: samples} = Trend.snapshot()
    {live, live_at} = latest || {nil, nil}

    {:ok,
     socket
     |> assign(live: live, live_at: live_at, samples: samples, offline?: false, now: now())
     |> assign(page_title: "Verbruik")
     |> assign_status()
     |> assign_usage()}
  end

  @impl true
  def handle_info({:telegram, telegram}, socket) do
    now = now()
    live = Meter.live(telegram)
    samples = Trend.prune(socket.assigns.samples ++ [{now, live.power_w}], now)

    {:noreply,
     socket
     |> assign(live: live, live_at: now, now: now, offline?: false, samples: samples)
     |> assign_status()}
  end

  def handle_info(:meter_offline, socket),
    do: {:noreply, socket |> assign(offline?: true) |> assign_status()}

  def handle_info(:tick, socket), do: handle_info({:tick, now()}, socket)

  def handle_info({:tick, now}, socket),
    do: {:noreply, socket |> assign(now: now) |> assign_status()}

  def handle_info({:recorded, _minute}, socket), do: {:noreply, assign_usage(socket)}

  defp assign_usage(socket) do
    tz = Application.fetch_env!(:mijnverbruik, :timezone)
    now = System.os_time(:second)
    first_hour = now - rem(now, 3600) - 23 * 3600
    by_hour = first_hour |> DateTime.from_unix!() |> Readings.hourly() |> Map.new(&{&1.hour, &1})

    hours =
      for hour <- first_hour..(first_hour + 23 * 3600)//3600 do
        usage = Map.get(by_hour, hour, %{delivered_wh: 0, returned_wh: 0, gas_l: 0})
        local = hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)
        Map.put(usage, :label, Calendar.strftime(local, "%H:00"))
      end

    days =
      for d <- Readings.daily(30, tz) do
        Map.put(d, :label, Calendar.strftime(d.date, "%a %d %b"))
      end

    assign(socket,
      today: Readings.today(tz),
      gas_flow_l: Readings.gas_flow(),
      hours: hours,
      days: days
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <section aria-labelledby="now" class="space-y-4">
        <h2 id="now" class="text-sm font-medium text-base-content/60">Now</h2>
        <%= if @live do %>
          <p
            :if={@status}
            id="meter-status"
            role="status"
            class="flex items-center gap-2 text-sm text-warning"
          >
            <.icon name="hero-signal-slash" class="size-4" />
            {@status}
          </p>
          <div class={[
            "space-y-4 transition-opacity",
            @status && "opacity-40"
          ]}>
            <p id="power" class="text-6xl font-semibold tabular-nums tracking-tight">
              {@live.power_w}<span class="ml-2 text-2xl font-normal text-base-content/60">W</span>
            </p>
            <.trend id="trend" samples={@samples} now={@now} window={Trend.window()} />
            <ul class="grid grid-cols-3 gap-3">
              <li
                :for={{phase, i} <- Enum.with_index(@live.phases, 1)}
                class="rounded-xl border border-base-300 p-3"
              >
                <p class="text-xs text-base-content/60">L{i}</p>
                <p class="text-lg font-medium tabular-nums">{phase.power_w} W</p>
                <p class="text-xs tabular-nums text-base-content/60">{phase.current_a} A</p>
              </li>
            </ul>
          </div>
        <% else %>
          <p id="power" class="text-base-content/60">Waiting for the meter…</p>
        <% end %>
        <div class="flex items-baseline justify-between rounded-xl border border-base-300 p-3">
          <p class="text-xs text-base-content/60">
            Gas <span class="text-base-content/40">· meter updates every 5 minutes</span>
          </p>
          <p id="gas-flow" class="text-lg font-medium tabular-nums">
            <%= if @gas_flow_l do %>
              {m3(@gas_flow_l)} m³/h
            <% else %>
              <span class="text-base-content/60" title="Waiting for two gas meter updates">—</span>
            <% end %>
          </p>
        </div>
      </section>

      <section aria-labelledby="today" class="mt-10 space-y-3">
        <h2 id="today" class="text-sm font-medium text-base-content/60">Today</h2>
        <dl class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <div class="rounded-xl border border-base-300 p-3">
            <dt class="text-xs text-base-content/60">Electricity</dt>
            <dd id="today-electricity" class="text-2xl font-medium tabular-nums">
              {kwh(@today.delivered_wh)} kWh
            </dd>
            <dd :if={@today.returned_wh > 0} class="text-xs tabular-nums text-base-content/60">
              {kwh(@today.returned_wh)} kWh returned
            </dd>
          </div>
          <div class="rounded-xl border border-base-300 p-3">
            <dt class="text-xs text-base-content/60">Gas</dt>
            <dd id="today-gas" class="text-2xl font-medium tabular-nums">
              {m3(@today.gas_l)} m³
            </dd>
          </div>
          <div class="col-span-2 rounded-xl border border-base-300 p-3 sm:col-span-1">
            <dt class="text-xs text-base-content/60">Costs</dt>
            <%= if @today.cost do %>
              <dd id="today-cost" class="text-2xl font-medium tabular-nums">{euro(@today.cost)}</dd>
              <dd class="text-xs text-base-content/60">incl. fixed costs</dd>
            <% else %>
              <dd id="today-cost" class="pt-1 text-sm">
                <.link navigate={~p"/settings"} class="link link-primary">Add your tariffs</.link>
              </dd>
            <% end %>
          </div>
        </dl>
      </section>

      <.bars id="hours" title="Electricity · last 24 hours" unit={:kwh} bars={electricity(@hours)} />
      <.bars id="hours-gas" title="Gas · last 24 hours" unit={:m3} bars={gas(@hours)} />
      <.bars id="days" title="Electricity · last 30 days" unit={:kwh} bars={electricity(@days)} />
      <.bars id="days-gas" title="Gas · last 30 days" unit={:m3} bars={gas(@days)} />
    </Layouts.app>
    """
  end

  defp electricity(usage),
    do: Enum.map(usage, &%{label: &1.label, up: &1.delivered_wh, down: &1.returned_wh})

  defp gas(usage), do: Enum.map(usage, &%{label: &1.label, up: &1.gas_l})

  # Telegrams arrive every second; 10 seconds without one means the values on
  # screen no longer describe now.
  @stale_after 10

  defp assign_status(%{assigns: %{live_at: nil}} = socket), do: assign(socket, status: nil)

  defp assign_status(%{assigns: %{offline?: offline?, live_at: live_at, now: now}} = socket) do
    age = now - live_at

    status =
      cond do
        offline? -> "Meter offline · last update #{ago(age)}"
        age > @stale_after -> "No data from the meter · last update #{ago(age)}"
        true -> nil
      end

    assign(socket, status: status)
  end

  defp ago(seconds) when seconds < 60, do: "#{max(seconds, 0)} s ago"
  defp ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min ago"
  defp ago(seconds), do: "#{div(seconds, 3600)} h ago"

  defp now, do: System.os_time(:second)
end
