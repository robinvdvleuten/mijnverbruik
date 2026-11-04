defmodule MijnverbruikWeb.DashboardLive do
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.{Charts, Format}

  alias Mijnverbruik.{Insights, Meter, Prices, Readings, Settings, Tariffs}
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
     |> assign(page_title: "Verbruik", fuse_a: Settings.get().main_fuse_a)
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

    assign(socket,
      today: Readings.today(tz),
      gas_flow_l: Readings.gas_flow(),
      hours: hours,
      insights: Insights.summary(tz),
      prices: prices(tz, now)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <ul :if={@insights.warnings != []} id="warnings" class="mb-8 space-y-3">
        <li
          :for={warning <- @insights.warnings}
          id={"warning-#{elem(warning, 0)}"}
          role="alert"
          class="flex gap-3 rounded-xl border border-warning/40 bg-warning/10 p-3 text-sm"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0 text-warning" />
          <div>{warning_text(warning)}</div>
        </li>
      </ul>

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
            <p
              :for={{phase, i} <- Enum.with_index(@live.phases, 1)}
              :if={load_level(phase.current_a, @fuse_a) == :critical}
              id={"fuse-warning-#{i}"}
              role="alert"
              class="flex gap-2 rounded-xl border border-error/40 bg-error/10 p-3 text-sm"
            >
              <.icon name="hero-bolt" class="mt-0.5 size-4 shrink-0 text-error" />
              L{i} draws {phase.current_a} A of its {@fuse_a} A fuse. Switch something off on this phase to keep the fuse from tripping.
            </p>
            <ul class="grid grid-cols-3 gap-3">
              <li
                :for={{phase, i} <- Enum.with_index(@live.phases, 1)}
                id={"phase-#{i}"}
                class="rounded-xl border border-base-300 p-3"
              >
                <p class="text-xs text-base-content/60">L{i}</p>
                <p class="text-lg font-medium tabular-nums">{phase.power_w} W</p>
                <p class="text-xs tabular-nums text-base-content/60">
                  {phase.current_a} A<span :if={@fuse_a}> of {@fuse_a} A</span>
                </p>
                <div
                  :if={@fuse_a}
                  class="mt-2 h-1.5 overflow-hidden rounded-full bg-base-300"
                  role="meter"
                  aria-label={"L#{i} load"}
                  aria-valuemin="0"
                  aria-valuemax={@fuse_a}
                  aria-valuenow={phase.current_a}
                >
                  <div
                    class={[
                      "h-full rounded-full transition-[width] duration-500",
                      case load_level(phase.current_a, @fuse_a) do
                        :critical -> "bg-error"
                        :high -> "bg-warning"
                        :normal -> "bg-primary"
                      end
                    ]}
                    style={"width: #{min(phase.current_a / @fuse_a * 100, 100)}%"}
                  />
                </div>
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
              <dd class="text-xs text-base-content/60">incl. fixed costs so far</dd>
            <% else %>
              <dd id="today-cost" class="pt-1 text-sm">
                <.link navigate={~p"/settings"} class="link link-primary">Add your tariffs</.link>
              </dd>
            <% end %>
          </div>
        </dl>
      </section>

      <section :if={@insights.standby_w} aria-labelledby="insights" class="mt-10 space-y-3">
        <h2 id="insights" class="text-sm font-medium text-base-content/60">Insights</h2>
        <div id="standby" class="rounded-xl border border-base-300 p-3">
          <div class="flex items-baseline justify-between gap-3">
            <p class="text-xs text-base-content/60">Standby power</p>
            <p :if={@insights.standby_cost_year} class="text-xs tabular-nums text-base-content/60">
              ≈ €{round(@insights.standby_cost_year)} per year
            </p>
          </div>
          <p class="text-2xl font-medium tabular-nums">{@insights.standby_w} W</p>
          <p class="mt-1 text-xs text-base-content/60">
            The lowest hourly use between midnight and 6:00 over the last 7 nights: devices that are always on.
          </p>
        </div>
      </section>

      <section :if={@prices} id="prices-section" class="mt-10">
        <p :if={@prices.now} class="text-sm">
          Electricity now costs
          <span id="price-now" class="font-medium tabular-nums">
            {euro(Enum.at(@prices.bars, @prices.now).price)}/kWh
          </span>
          <span :if={@prices.cheapest} class="text-base-content/60">
            · cheapest {@prices.cheapest.label} at {euro(@prices.cheapest.price)}/kWh
          </span>
        </p>
        <.bars
          id="prices"
          title="Electricity price · today and tomorrow"
          unit={:eur_kwh}
          bars={@prices.bars}
          highlight={@prices.now}
        />
      </section>

      <.bars id="hours" title="Electricity · last 24 hours" unit={:kwh} bars={electricity(@hours)} />
      <.bars id="hours-gas" title="Gas · last 24 hours" unit={:m3} bars={gas(@hours)} />
      <.link
        navigate={~p"/history"}
        id="history-link"
        class="mt-6 inline-flex items-center gap-1 text-sm link link-hover text-base-content/60"
      >
        Days, weeks, months and years in History <.icon name="hero-arrow-right" class="size-4" />
      </.link>
    </Layouts.app>
    """
  end

  # Fraction of the main fuse a phase may draw before it shows as high or
  # critical. Fuses trip on sustained overload, so these are early warnings.
  @load_high 0.8
  @load_critical 0.95

  defp load_level(_current, nil), do: nil
  defp load_level(current, fuse) when current >= fuse * @load_critical, do: :critical
  defp load_level(current, fuse) when current >= fuse * @load_high, do: :high
  defp load_level(_current, _fuse), do: :normal

  defp warning_text({:standby_high, last_night, usual}) do
    "Standby power was #{last_night} W last night, against #{round(usual)} W usually. Something may have been left on."
  end

  defp warning_text({:gas_at_night, litres}) do
    "Gas flowed steadily between 01:00 and 05:00 last night (#{litres} litres). If your heating and hot water were off, check for a gas leak."
  end

  # All-in hourly electricity prices for today and tomorrow (once published)
  # when today's tariff is dynamic, as chart bars with the current hour's index.
  defp prices(tz, now) do
    today = tz |> DateTime.now!() |> DateTime.to_date()

    with %{contract: :dynamic} = tariff <- Tariffs.valid_on(Tariffs.list_tariffs(), today),
         start = today |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix(),
         stop = today |> Date.add(2) |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix(),
         market when map_size(market) > 0 <- Prices.between(start, stop) do
      bars =
        for {hour, price} <- Enum.sort(market) do
          local = hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)
          all_in = Tariffs.kwh_price(tariff, price)
          day = if DateTime.to_date(local) == today, do: "today", else: "tomorrow"

          %{
            hour: hour,
            label: "#{day} #{Calendar.strftime(local, "%H:00")}",
            up: max(all_in, 0),
            down: max(-all_in, 0),
            price: all_in
          }
        end

      %{
        bars: bars,
        now: Enum.find_index(bars, &(&1.hour <= now and now < &1.hour + 3600)),
        cheapest:
          Enum.min_by(Enum.filter(bars, &(&1.hour + 3600 > now)), & &1.price, fn -> nil end)
      }
    else
      _ -> nil
    end
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
