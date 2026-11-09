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
     |> assign(page_title: "Nu", fuse_a: Settings.get().main_fuse_a, tz: timezone())
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

  # Telegrams arrive every second; 10 seconds without one means the values on
  # screen no longer describe now. After 5 minutes a banner says so too.
  @stale_after 10
  @banner_after 300

  defp assign_status(%{assigns: %{live_at: nil}} = socket),
    do: assign(socket, state: :waiting, banner?: false)

  defp assign_status(%{assigns: %{offline?: offline?, live_at: live_at, now: now}} = socket) do
    age = now - live_at
    stale? = offline? or age > @stale_after

    assign(socket,
      state: if(stale?, do: :stale, else: :live),
      banner?: offline? or age >= @banner_after
    )
  end

  defp assign_usage(socket) do
    tz = socket.assigns.tz
    now = System.os_time(:second)
    today = tz |> DateTime.now!() |> DateTime.to_date()
    tariff = Tariffs.valid_on(Tariffs.list_tariffs(), today)
    # The last 24 hours, ending with the current hour.
    first = now - rem(now, 3600) - 23 * 3600
    from = DateTime.from_unix!(first)

    by_hour = from |> Readings.hourly() |> Map.new(&{&1.hour, &1})

    gas_hours =
      for hour <- first..(first + 23 * 3600)//3600 do
        %{label: local_time(hour, tz, "%H:00"), up: get_in(by_hour, [hour, :gas_l]) || 0}
      end

    # The running 5 minutes are left out: as an average power they would read
    # too low until complete.
    by_minute =
      from
      |> Readings.five_minutes(DateTime.from_unix!(now - rem(now, 300)))
      |> Map.new(&{&1.minute, &1})

    assign(socket,
      today: Readings.today(tz),
      gas_flow_l: Readings.gas_flow(),
      electricity: quarters(first, by_minute, tz),
      electricity_ticks:
        for(k <- 0..5, do: local_time(first + k * 4 * 3600, tz, "%H:00")) ++ ["nu"],
      gas_hours: gas_hours,
      gas_ticks: [hd(gas_hours).label, Enum.at(gas_hours, 12).label, "nu"],
      insights: Insights.summary(tz),
      tariff: tariff,
      prices: tariff && prices(tariff, today, tz, now),
      gas_price: tariff && gas_price(tariff, now)
    )
  end

  # Average net power per quarter hour, from the 5-minute usage: Wh over
  # 5 minutes, times 12, is the average power in W.
  defp quarters(first, by_minute, tz) do
    for quarter <- first..(first + 24 * 3600 - 900)//900 do
      parts = for m <- [quarter, quarter + 300, quarter + 600], u = by_minute[m], do: u
      label = local_time(quarter, tz, "%H:%M")

      if parts == [] do
        %{label: label, up: nil, down: 0}
      else
        net =
          Enum.sum_by(parts, &(&1.delivered_wh - &1.returned_wh)) * 12 / length(parts)

        %{label: label, up: max(net, 0), down: max(-net, 0)}
      end
    end
  end

  # Today's all-in hourly electricity prices when the tariff is dynamic, as
  # 24 bars toned past, now, cheapest still to come and future.
  defp prices(%{contract: :dynamic} = tariff, today, tz, now) do
    start = today |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    stop = today |> Date.add(1) |> DateTime.new!(~T[00:00:00], tz) |> DateTime.to_unix()
    market = Prices.between(start, stop)

    if map_size(market) > 0 do
      current = now - rem(now, 3600)

      hours =
        for hour <- start..(stop - 3600)//3600 do
          price = market[hour] && Tariffs.kwh_price(tariff, market[hour])
          %{hour: hour, price: price, label: local_time(hour, tz, "%H:00")}
        end

      cheapest =
        hours
        |> Enum.filter(&(&1.price && &1.hour > current))
        |> Enum.min_by(& &1.price, fn -> nil end)

      bars =
        for h <- hours do
          tone =
            cond do
              h.hour == current -> :now
              cheapest && h.hour == cheapest.hour -> :cheap
              h.hour < current -> :past
              true -> :future
            end

          %{
            label: h.label,
            up: h.price && max(h.price, 0),
            down: if(h.price, do: max(-h.price, 0), else: 0),
            tone: tone
          }
        end

      %{bars: bars, now: Enum.find(hours, &(&1.hour == current)), cheapest: cheapest}
    end
  end

  defp prices(_tariff, _today, _tz, _now), do: nil

  # The current all-in gas price; for a dynamic gas contract only once the
  # gas day's market price is known.
  defp gas_price(%{gas_contract: :dynamic} = tariff, now) do
    hour = now - rem(now, 3600)

    case Prices.between(hour, hour + 3600, :gas) do
      %{^hour => market} -> Tariffs.m3_price(tariff, market)
      _ -> nil
    end
  end

  defp gas_price(tariff, _now), do: Tariffs.m3_price(tariff, nil)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        mode: mode(assigns),
        phases: if(assigns.live, do: assigns.live.phases, else: []),
        standby: assigns.insights.standby_w
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      active={:dashboard}
      meter={
        case @state do
          :live -> :live
          :stale -> :offline
          :waiting -> nil
        end
      }
    >
      <.banner :if={@banner?} id="offline-banner" title="Meter niet bereikbaar">
        Laatste meting om {local_time(@live_at, @tz, "%H:%M")}, {ago(@now - @live_at)} geleden. Live waarden staan stil tot de meter weer data stuurt.
      </.banner>

      <.banner
        :for={{:gas_at_night, litres} <- @insights.warnings}
        id="warning-gas_at_night"
        title="Gas in de nacht"
      >
        Tussen 01:00 en 05:00 stroomde er gelijkmatig gas ({litres} liter). Stonden verwarming en warm water uit? Laat dan controleren op een gaslek.
      </.banner>

      <.hero
        now={@now}
        tz={@tz}
        mode={@mode}
        state={@state}
        live={@live}
        live_at={@live_at}
        standby={@standby}
        returned_wh={@today.returned_wh}
      />

      <div class="relative mx-auto -mt-1 w-full max-w-[340px] sm:max-w-[600px]">
        <.flow layout={:narrow} class="sm:hidden" {flow_assigns(assigns)} />
        <.flow layout={:wide} class="hidden sm:block" {flow_assigns(assigns)} />
      </div>

      <.banner
        :for={{phase, i} <- Enum.with_index(@phases, 1)}
        :if={load_level(phase.current_a, @fuse_a) == :critical}
        id={"fuse-warning-#{i}"}
        title={"L#{i} bijna op de limiet"}
        tone={:danger}
      >
        L{i} trekt {decimal(phase.current_a, 1)} A van de {@fuse_a} A zekering. Zet iets uit op deze fase zodat de zekering niet springt.
      </.banner>

      <dl id="today" class="grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
        <.tile
          dot="bg-use"
          label="Afgenomen"
          id="today-electricity"
          value={kwh(@today.delivered_wh)}
          unit="kWh"
        />
        <.tile
          dot="bg-return"
          label="Teruggeleverd"
          id="today-returned"
          value={kwh(@today.returned_wh)}
          unit="kWh"
        />
        <.tile dot="bg-gas" label="Gas" id="today-gas" value={m3(@today.gas_l)} unit="m³" />
        <div class="min-w-0 rounded-3xl border border-tile-line bg-tile px-5 py-[18px] backdrop-blur-xl">
          <dt class="flex items-center gap-[7px] text-[13px] text-muted">
            <.dot class="bg-cost" />Kosten
          </dt>
          <dd id="today-cost" class="mt-1.5">
            <%= if @today.cost do %>
              <span class="text-2xl font-bold leading-none tracking-[-0.035em] md:text-[32px]">
                {euro(@today.cost)}
              </span>
            <% else %>
              <.link
                navigate={~p"/settings"}
                class="text-sm font-bold text-cost-ink underline-offset-4 hover:underline"
              >
                Tarieven instellen
              </.link>
            <% end %>
          </dd>
        </div>
      </dl>

      <aside
        :for={{:standby_high, last_night, usual} <- @insights.warnings}
        id="tip"
        class="flex flex-col gap-2 rounded-3xl bg-tip px-6 py-5 text-on-tip sm:flex-row sm:items-center sm:gap-6 sm:px-7 sm:py-6"
      >
        <span class="font-mono text-[11px]">Tip</span>
        <p class="text-lg font-bold leading-tight text-pretty sm:text-[22px]">
          Je sluipverbruik was vannacht {last_night} W, normaal is dat {round(usual)} W. Staat er iets aan dat uit kan?
        </p>
      </aside>

      <.card id="electricity-card" class="h-64 sm:h-[290px]">
        <:title>Elektriciteit · 24 uur</:title>
        <:aside>
          <span class="flex items-center gap-3 font-sans text-xs text-muted">
            <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-[3px] bg-use" />Afname</span>
            <span class="flex items-center gap-1.5"><span class="size-2.5 rounded-[3px] bg-return" />Terug</span>
          </span>
        </:aside>
        <.bars
          id="electricity"
          label="Elektriciteit over de laatste 24 uur, gemiddeld vermogen per kwartier"
          unit={:w}
          bars={@electricity}
          ticks={@electricity_ticks}
          class="flex-1"
        />
      </.card>

      <div class={[
        "grid gap-3 md:gap-4",
        if(length(middle(@phases, @standby)) == 3, do: "md:grid-cols-3", else: "md:grid-cols-2")
      ]}>
        <.card id="gas-card" class="h-56 md:h-60">
          <:title>Gas</:title>
          <:aside>
            <span :if={@gas_price} id="gas-price">{euro(@gas_price)}/m³</span>
            <span :if={!@gas_price}>per uur</span>
          </:aside>
          <.figure value={m3(@today.gas_l)} unit="m³ vandaag" />
          <.bars
            id="hours-gas"
            label="Gas per uur over de laatste 24 uur"
            unit={:m3}
            color={:gas}
            bars={@gas_hours}
            ticks={@gas_ticks}
            class="flex-1"
          />
        </.card>

        <.price_card prices={@prices} tariff={@tariff} gas_price={@gas_price} />

        <%= if :phases in middle(@phases, @standby) do %>
          <.phases_card phases={@phases} fuse_a={@fuse_a} stale={@state == :stale} />
        <% end %>
        <%= if :standby in middle(@phases, @standby) do %>
          <.standby_card insights={@insights} tall />
        <% end %>
      </div>

      <div class={[
        "grid gap-3 md:gap-4",
        @standby && :phases in middle(@phases, @standby) &&
          "md:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]"
      ]}>
        <.standby_card :if={@standby && :phases in middle(@phases, @standby)} insights={@insights} />
        <.card id="trend-card" class="h-[130px]">
          <:title>Laatste 5 min</:title>
          <:aside :if={@samples != []}>
            <span class="text-use-ink">piek {watts(@samples |> Enum.map(&elem(&1, 1)) |> Enum.max())} W</span>
          </:aside>
          <.trend
            id="trend"
            samples={@samples}
            now={@now}
            window={Trend.window()}
            stale={@state == :stale}
            class="flex-1"
          />
        </.card>
      </div>

      <.link
        navigate={~p"/history"}
        id="history-link"
        class="group mt-2 inline-flex items-center gap-1.5 self-center text-sm font-semibold text-muted transition-colors hover:text-ink"
      >
        Dagen, weken, maanden en jaren in Geschiedenis
        <.icon
          name="hero-arrow-right-mini"
          class="size-4 transition-transform group-hover:translate-x-0.5"
        />
      </.link>
    </Layouts.app>
    """
  end

  # The cards in the middle row next to gas and prices: phase load for homes
  # with three phases, else standby power, which then leaves the bottom row.
  defp middle(phases, standby) do
    cond do
      length(phases) > 1 -> [:gas, :price, :phases]
      standby -> [:gas, :price, :standby]
      true -> [:gas, :price]
    end
  end

  # What the hero shows: return to the grid, use from the grid while panels
  # produced today (so the grid is not all the home uses), or, without return,
  # the home's use, which then equals what comes from the grid.
  defp mode(%{live: nil}), do: :waiting
  defp mode(%{live: %{power_w: w}}) when w < 0, do: :return
  defp mode(%{today: %{returned_wh: r}}) when r > 0, do: :import
  defp mode(_assigns), do: :home

  defp hero(assigns) do
    ~H"""
    <section aria-labelledby="hero-title" class="flex flex-col items-center gap-1.5 text-center">
      <p class="text-base text-muted">{greeting(@now, @tz)}</p>
      <h1 id="hero-title" class="mb-2 text-[19px] font-semibold">
        {hero_title(@mode, @state)}
      </h1>
      <p class="flex items-baseline gap-1.5">
        <span
          id="power"
          class={[
            "text-[68px] font-bold leading-none tracking-[-0.035em] transition-colors sm:text-8xl",
            @state == :stale && "text-subtle"
          ]}
        >
          {if @live, do: watts(abs(@live.power_w)), else: "—"}
        </span>
        <span class={[
          "text-2xl font-semibold sm:text-[35px]",
          cond do
            @state == :stale -> "text-subtle"
            @mode == :return -> "text-return"
            true -> "text-use"
          end
        ]}>
          W
        </span>
      </p>
      <p
        :if={@state == :stale}
        id="meter-status"
        role="status"
        class="mt-1.5 text-[15px] text-warn-ink"
      >
        Laatste meting om {local_time(@live_at, @tz, "%H:%M")}
      </p>
      <p :if={@state != :stale} class="mt-1.5 max-w-[460px] text-[15px] text-muted text-pretty">
        {hero_note(@mode, @standby, @returned_wh)}
      </p>
    </section>
    """
  end

  defp hero_title(:waiting, _state), do: "Wachten op de meter"
  defp hero_title(:return, :stale), do: "Teruggeleverd, laatst gemeten"
  defp hero_title(:import, :stale), do: "Uit het net, laatst gemeten"
  defp hero_title(:home, :stale), do: "Thuis, laatst gemeten"
  defp hero_title(:return, _state), do: "Nu teruggeleverd"
  defp hero_title(:import, _state), do: "Nu uit het net"
  defp hero_title(:home, _state), do: "Thuis gebruikt nu"

  defp hero_note(:waiting, _standby, _returned),
    do: "Zodra de slimme meter data stuurt, zie je hier je verbruik."

  defp hero_note(:return, _standby, _returned),
    do: "Je zonnepanelen leveren meer dan je huis nu gebruikt."

  # The grid is only part of the home's use while panels produce, so the
  # note shows what they returned today rather than a total it cannot know.
  defp hero_note(:import, _standby, returned),
    do: "Vandaag al #{kwh(returned)} kWh teruggeleverd."

  defp hero_note(:home, nil, _returned), do: "Alles wat nu aan staat."

  defp hero_note(:home, standby, _returned),
    do: "Alles wat nu aan staat. #{standby} W daarvan is altijd aan."

  defp greeting(now, tz) do
    local = now |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)

    part =
      cond do
        local.hour < 6 -> "Goedenacht"
        local.hour < 12 -> "Goedemorgen"
        local.hour < 18 -> "Goedemiddag"
        true -> "Goedenavond"
      end

    "#{part} · #{day_month(DateTime.to_date(local))}"
  end

  defp flow_assigns(assigns) do
    %{
      mode: assigns.mode,
      stale: assigns.state == :stale,
      power_w: assigns.live && assigns.live.power_w,
      gas_flow_l: assigns.gas_flow_l
    }
  end

  attr :layout, :atom, values: [:wide, :narrow], required: true
  attr :class, :any, required: true
  attr :mode, :atom, required: true
  attr :stale, :boolean, required: true
  attr :power_w, :integer, required: true
  attr :gas_flow_l, :any, required: true

  # Energy flowing between the grid, gas and the home. Lines run towards the
  # home and thicken with the power; return runs back towards the grid.
  defp flow(assigns) do
    geometry =
      case assigns.layout do
        :wide ->
          %{
            box: {600, 290},
            net: {14, 110},
            gas: {474, 110},
            orb: {220, 65, 160},
            net_path: "M126 145 C213 145 213 145 300 145",
            gas_path: "M474 145 C387 145 387 145 300 145"
          }

        :narrow ->
          %{
            box: {340, 260},
            net: {0, 75},
            gas: {169, 186},
            orb: {157, 42, 136},
            net_path: "M112 110 C168.5 110 168.5 110 225 110",
            gas_path: "M225 186 C225 186 225 178 225 178"
          }
      end

    watts = abs(assigns.power_w || 0)
    active? = not assigns.stale and assigns.mode != :waiting
    gas? = not assigns.stale and (assigns.gas_flow_l || 0) > 0

    assigns =
      assign(assigns,
        g: geometry,
        active?: active?,
        gas?: gas?,
        width: min(3 + watts / 250, 10),
        dash: if(watts > 800, do: 4, else: 3),
        # Faster for more power: 2 s at rest down to 0.8 s at 2 kW and up.
        speed: max(2 - watts / 1700, 0.8),
        line: if(assigns.mode == :return, do: "stroke-return", else: "stroke-use")
      )

    ~H"""
    <div
      class={["relative max-w-full", @class]}
      style={"width: #{elem(@g.box, 0)}px; height: #{elem(@g.box, 1)}px"}
      aria-hidden="true"
    >
      <svg
        width={elem(@g.box, 0)}
        height={elem(@g.box, 1)}
        viewBox={"0 0 #{elem(@g.box, 0)} #{elem(@g.box, 1)}"}
        class="absolute inset-0 overflow-visible"
      >
        <%= if @active? do %>
          <path
            d={@g.net_path}
            fill="none"
            class={@line}
            stroke-width={@width}
            stroke-linecap="round"
            opacity=".28"
          />
          <path
            d={@g.net_path}
            fill="none"
            class={[@line, if(@mode == :return, do: "animate-flow-back", else: "animate-flow")]}
            stroke-width={@dash}
            stroke-linecap="round"
            stroke-dasharray="2 10"
            style={"animation-duration: #{@speed}s"}
          />
        <% else %>
          <path
            d={@g.net_path}
            fill="none"
            class="stroke-ink"
            stroke-width="2"
            stroke-dasharray="3 8"
            opacity=".28"
          />
        <% end %>
        <%= if @gas? do %>
          <path
            d={@g.gas_path}
            fill="none"
            class="stroke-gas"
            stroke-width="3"
            stroke-linecap="round"
            opacity=".28"
          />
          <path
            d={@g.gas_path}
            fill="none"
            class="stroke-gas animate-flow"
            stroke-width="3"
            stroke-linecap="round"
            stroke-dasharray="2 10"
            style="animation-duration: 2s"
          />
        <% else %>
          <path
            d={@g.gas_path}
            fill="none"
            class="stroke-ink"
            stroke-width="2"
            stroke-dasharray="3 8"
            opacity=".28"
          />
        <% end %>
      </svg>

      <.flow_node
        at={@g.net}
        stale={@stale}
        dot={if(@mode == :return, do: "bg-return", else: "bg-use")}
        label="Net"
      >
        <%= if @power_w do %>
          {if @power_w < 0, do: "−"}{watts(abs(@power_w))} W
        <% else %>
          —
        <% end %>
      </.flow_node>
      <.flow_node at={@g.gas} stale={@stale} dot="bg-gas" label="Gas">
        <%= if @gas_flow_l do %>
          {m3(@gas_flow_l)} m³/u
        <% else %>
          —
        <% end %>
      </.flow_node>

      <div
        :if={!@stale}
        class="pointer-events-none absolute rounded-full border-2 border-inverse/35 animate-halo"
        style={orb_style(@g.orb)}
      />
      <div
        class={[
          "absolute flex flex-col items-center justify-center gap-0.5 rounded-full shadow-orb transition-colors duration-500",
          if(@stale, do: "bg-stale text-white", else: "bg-inverse text-on-inverse animate-breathe")
        ]}
        style={orb_style(@g.orb)}
      >
        <span class="text-[13px] opacity-75">Thuis</span>
        <span class={[
          "font-bold leading-none tracking-[-0.03em]",
          if(@layout == :wide, do: "text-[26px]", else: "text-[22px]")
        ]}>
          <%= cond do %>
            <% @power_w == nil -> %>
              —
            <% @power_w < 0 -> %>
              <span class="text-sm tracking-normal">op zonnestroom</span>
            <% @mode == :import -> %>
              <span class="mr-0.5 text-base font-semibold opacity-70">≥</span>{watts(@power_w)}<span class="ml-0.5 text-[11px] font-semibold opacity-80">W</span>
            <% true -> %>
              {watts(@power_w)}<span class="ml-0.5 text-[11px] font-semibold opacity-80">W</span>
          <% end %>
        </span>
      </div>
    </div>
    """
  end

  defp orb_style({left, top, size}),
    do: "left: #{left}px; top: #{top}px; width: #{size}px; height: #{size}px"

  attr :at, :any, required: true
  attr :stale, :boolean, required: true
  attr :dot, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp flow_node(assigns) do
    ~H"""
    <div
      class={[
        "absolute flex h-[70px] w-28 flex-col justify-center gap-[3px] rounded-[20px] border border-node-line bg-node px-3.5 shadow-tile transition-opacity",
        @stale && "opacity-60"
      ]}
      style={"left: #{elem(@at, 0)}px; top: #{elem(@at, 1)}px"}
    >
      <span class="flex items-center gap-1.5 text-[13px] font-semibold">
        <.dot class={if(@stale, do: "bg-subtle", else: @dot)} />{@label}
      </span>
      <span class="whitespace-nowrap font-mono text-[13px]">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :dot, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, required: true

  defp tile(assigns) do
    ~H"""
    <div class="min-w-0 rounded-3xl border border-tile-line bg-tile px-5 py-[18px] backdrop-blur-xl">
      <dt class="flex items-center gap-[7px] text-[13px] text-muted">
        <.dot class={@dot} />{@label}
      </dt>
      <dd class="mt-1.5 flex items-baseline gap-1.5">
        <span id={@id} class="text-2xl font-bold leading-none tracking-[-0.035em] md:text-[32px]">
          {@value}
        </span>
        <span class="text-[11px] font-semibold text-muted md:text-xs">{@unit}</span>
      </dd>
    </div>
    """
  end

  attr :prices, :map, required: true
  attr :tariff, :any, required: true
  attr :gas_price, :any, required: true

  defp price_card(%{prices: %{}} = assigns) do
    ~H"""
    <.card id="prices-card" class="h-56 md:h-60">
      <:title>Stroomprijs</:title>
      <:aside :if={@prices.now && @prices.now.price}>
        <span class="flex items-baseline gap-1.5 font-sans">
          <span id="price-now" class="text-[22px] font-bold leading-none tracking-[-0.035em] text-ink">
            {euro(@prices.now.price)}
          </span>
          <span class="text-[11px] font-semibold text-muted">nu</span>
        </span>
      </:aside>
      <p :if={@prices.cheapest} class="-mt-1 text-xs font-semibold text-return-ink">
        Goedkoopst {@prices.cheapest.label} · {euro(@prices.cheapest.price)}
      </p>
      <.bars
        id="prices"
        label="Stroomprijs per uur vandaag"
        unit={:eur_kwh}
        bars={@prices.bars}
        ticks={["00", "12", "24"]}
        class="flex-1"
      />
    </.card>
    """
  end

  defp price_card(%{tariff: nil} = assigns) do
    ~H"""
    <.card id="prices-card" class="md:h-60">
      <:title>Tarief</:title>
      <p class="text-sm text-muted text-pretty">
        Voeg je energietarieven toe om je kosten en de stroomprijs te zien.
      </p>
      <.button navigate={~p"/settings"} variant="primary" class="mt-auto self-start">
        Tarieven instellen
      </.button>
    </.card>
    """
  end

  defp price_card(assigns) do
    ~H"""
    <.card id="prices-card" class="justify-between md:h-60">
      <:title>Tarief</:title>
      <:aside>
        {if @tariff.contract == :dynamic, do: "dynamisch contract", else: "vast contract"}
      </:aside>
      <div class="flex flex-col gap-3.5">
        <div class="flex flex-col gap-1">
          <span class="text-[13px] text-muted">Stroom</span>
          <%= if @tariff.contract == :dynamic do %>
            <p class="text-sm text-muted">Nog geen marktprijzen voor vandaag.</p>
          <% else %>
            <p class="flex items-baseline gap-1.5">
              <.figure value={euro(Decimal.to_float(@tariff.electricity_normal))} unit="/kWh" />
              <span
                :if={Decimal.compare(@tariff.electricity_low, @tariff.electricity_normal) != :eq}
                class="font-mono text-[11px] text-subtle"
              >
                dal {euro(Decimal.to_float(@tariff.electricity_low))}
              </span>
            </p>
          <% end %>
        </div>
        <div :if={@gas_price} class="flex flex-col gap-1">
          <span class="text-[13px] text-muted">Gas</span>
          <.figure value={euro(@gas_price)} unit="/m³" />
        </div>
      </div>
    </.card>
    """
  end

  attr :phases, :list, required: true
  attr :fuse_a, :any, required: true
  attr :stale, :boolean, required: true

  defp phases_card(assigns) do
    ~H"""
    <.card id="phases" class="justify-center gap-3 md:h-60">
      <:title><span class="text-[15px]">Fasen</span></:title>
      <:aside :if={@fuse_a}>zekering {@fuse_a} A</:aside>
      <ul class="grid gap-2.5">
        <li
          :for={{phase, i} <- Enum.with_index(@phases, 1)}
          id={"phase-#{i}"}
          class="flex min-w-0 flex-col gap-[5px]"
        >
          <p class="flex justify-between gap-1.5 font-mono text-[11px]">
            <span>L{i}</span>
            <span class="text-muted">{watts(phase.power_w)} W · {decimal(phase.current_a, 1)} A</span>
          </p>
          <div
            :if={@fuse_a}
            class="h-[7px] overflow-hidden rounded bg-track"
            role="meter"
            aria-label={"Belasting L#{i}"}
            aria-valuemin="0"
            aria-valuemax={@fuse_a}
            aria-valuenow={phase.current_a}
          >
            <div
              class={[
                "h-full rounded transition-[width,background-color] duration-500",
                cond do
                  @stale -> "bg-stale"
                  load_level(phase.current_a, @fuse_a) == :critical -> "bg-danger"
                  load_level(phase.current_a, @fuse_a) == :high -> "bg-warn"
                  true -> "bg-use"
                end
              ]}
              style={"width: #{min(phase.current_a / @fuse_a * 100, 100)}%"}
            />
          </div>
        </li>
      </ul>
    </.card>
    """
  end

  attr :insights, :map, required: true
  attr :tall, :boolean, default: false

  defp standby_card(assigns) do
    ~H"""
    <section
      id="standby"
      class={[
        "flex min-w-0 gap-3 rounded-3xl border border-tile-line bg-tile px-5 py-[18px] backdrop-blur-xl sm:px-[22px]",
        if(@tall,
          do: "flex-col items-start justify-between md:h-60",
          else: "items-center justify-between md:h-[130px]"
        )
      ]}
    >
      <div class="flex flex-col gap-1">
        <h2 class="text-[15px] font-bold tracking-[-0.01em]">Sluipverbruik</h2>
        <p
          :if={@insights.standby_cost_year}
          class="whitespace-nowrap font-mono text-[11px] text-cost-ink"
        >
          ≈ € {round(@insights.standby_cost_year)} per jaar
        </p>
      </div>
      <.figure
        value={watts(@insights.standby_w)}
        unit="W"
        size={if(@tall, do: "text-[44px]", else: "text-[34px]")}
      />
      <p :if={@tall} class="text-xs text-muted text-pretty">
        Laagste uurverbruik ’s nachts, laatste 7 nachten
      </p>
    </section>
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

  defp ago(seconds) when seconds < 60, do: "#{max(seconds, 0)} seconden"
  defp ago(seconds) when seconds < 120, do: "1 minuut"
  defp ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} minuten"
  defp ago(seconds) when seconds < 7200, do: "1 uur"
  defp ago(seconds), do: "#{div(seconds, 3600)} uur"

  defp local_time(unix, tz, format) do
    unix |> DateTime.from_unix!() |> DateTime.shift_zone!(tz) |> Calendar.strftime(format)
  end

  defp timezone, do: Application.fetch_env!(:mijnverbruik, :timezone)

  defp now, do: System.os_time(:second)
end
