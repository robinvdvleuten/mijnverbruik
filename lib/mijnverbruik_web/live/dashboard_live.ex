defmodule MijnverbruikWeb.DashboardLive do
  use MijnverbruikWeb, :live_view

  alias Mijnverbruik.{Meter, Readings}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Meter.subscribe()
      Readings.subscribe()
    end

    {:ok, socket |> assign(live: nil, page_title: "Verbruik") |> assign_usage()}
  end

  @impl true
  def handle_info({:telegram, telegram}, socket),
    do: {:noreply, assign(socket, live: Meter.live(telegram))}

  def handle_info({:recorded, _minute}, socket), do: {:noreply, assign_usage(socket)}

  defp assign_usage(socket) do
    tz = Application.fetch_env!(:mijnverbruik, :timezone)
    now = System.os_time(:second)
    first_hour = now - rem(now, 3600) - 23 * 3600
    by_hour = first_hour |> DateTime.from_unix!() |> Readings.hourly() |> Map.new(&{&1.hour, &1})

    hours =
      for hour <- first_hour..(first_hour + 23 * 3600)//3600 do
        usage = Map.get(by_hour, hour, %{delivered_wh: 0})
        local = hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)
        %{label: Calendar.strftime(local, "%H:00"), value: usage.delivered_wh}
      end

    days =
      for d <- Readings.daily(30, tz) do
        %{label: Calendar.strftime(d.date, "%a %d %b"), value: d.delivered_wh}
      end

    assign(socket, today: Readings.today(tz), hours: hours, days: days)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section aria-labelledby="now" class="space-y-4">
        <h2 id="now" class="text-sm font-medium text-base-content/60">Now</h2>
        <%= if @live do %>
          <p id="power" class="text-6xl font-semibold tabular-nums tracking-tight">
            {@live.power_w}<span class="ml-2 text-2xl font-normal text-base-content/60">W</span>
          </p>
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
        <% else %>
          <p id="power" class="text-base-content/60">Waiting for the meter…</p>
        <% end %>
      </section>

      <section aria-labelledby="today" class="mt-10 space-y-3">
        <h2 id="today" class="text-sm font-medium text-base-content/60">Today</h2>
        <dl class="grid grid-cols-2 gap-3">
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
        </dl>
      </section>

      <.bars id="hours" title="Last 24 hours" bars={@hours} />
      <.bars id="days" title="Last 30 days" bars={@days} />
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :bars, :list, required: true, doc: "maps with :label and :value (Wh)"

  defp bars(assigns) do
    max = assigns.bars |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end) |> max(1)
    assigns = assign(assigns, max: max, width: 100 / max(length(assigns.bars), 1))

    ~H"""
    <section aria-labelledby={"#{@id}-title"} class="mt-10 space-y-3">
      <div class="flex items-baseline justify-between">
        <h2 id={"#{@id}-title"} class="text-sm font-medium text-base-content/60">{@title}</h2>
        <p class="text-xs tabular-nums text-base-content/60">max {kwh(@max)} kWh</p>
      </div>
      <svg
        id={@id}
        viewBox="0 0 100 40"
        preserveAspectRatio="none"
        class="h-40 w-full text-primary"
        role="img"
        aria-label={"#{@title}, electricity per bar in kWh"}
      >
        <rect
          :for={{bar, i} <- Enum.with_index(@bars)}
          x={i * @width + @width * 0.1}
          y={40 - bar.value / @max * 40}
          width={@width * 0.8}
          height={bar.value / @max * 40}
          fill="currentColor"
          rx="0.5"
        >
          <title>{bar.label}: {kwh(bar.value)} kWh</title>
        </rect>
      </svg>
      <div class="flex justify-between text-xs text-base-content/60">
        <span>{List.first(@bars).label}</span>
        <span>{List.last(@bars).label}</span>
      </div>
    </section>
    """
  end

  defp kwh(wh), do: :erlang.float_to_binary(wh / 1000, decimals: 2)
  defp m3(l), do: :erlang.float_to_binary(l / 1000, decimals: 2)
end
