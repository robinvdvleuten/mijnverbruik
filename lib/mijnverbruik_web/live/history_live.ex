defmodule MijnverbruikWeb.HistoryLive do
  @moduledoc """
  Usage and costs per day, week, month or year, compared with the period
  before. The period and its date live in the URL, e.g.
  `/history?period=week&date=2026-11-02`.
  """
  use MijnverbruikWeb, :live_view

  import MijnverbruikWeb.{Charts, Format}

  alias Mijnverbruik.Readings

  @periods ~w(day week month year)

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Geschiedenis")}

  @impl true
  def handle_params(params, _uri, socket) do
    tz = timezone()
    today = tz |> DateTime.now!() |> DateTime.to_date()
    period = if params["period"] in @periods, do: params["period"], else: "day"

    first =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, date} -> start_of(period, date)
        _ -> start_of(period, today)
      end

    current = buckets(period, first, tz)
    previous = buckets(period, shift(period, first, -1), tz)

    # Compare like for like: while a period is still running, only the part
    # of the previous period that has elapsed in this one counts.
    elapsed = Enum.count(current, &(not future?(&1, today)))
    partial? = elapsed < length(current)

    {:noreply,
     assign(socket,
       period: period,
       first: first,
       today: today,
       current: current,
       previous: previous,
       totals: Readings.total(current),
       previous_totals: previous |> Enum.take(elapsed) |> Readings.total(),
       partial?: partial?,
       now: partial? && now_position(period, current, tz),
       next?: Date.compare(shift(period, first, 1), today) != :gt
     )}
  end

  defp history_path(period, date),
    do: ~p"/history?#{[period: period, date: Date.to_iso8601(date)]}"

  defp start_of("day", date), do: date
  defp start_of("week", date), do: Date.beginning_of_week(date)
  defp start_of("month", date), do: Date.beginning_of_month(date)
  defp start_of("year", date), do: Date.new!(date.year, 1, 1)

  defp shift("day", date, n), do: Date.add(date, n)
  defp shift("week", date, n), do: Date.add(date, 7 * n)
  defp shift("month", date, n), do: Date.shift(date, month: n)
  defp shift("year", date, n), do: Date.shift(date, year: n)

  defp buckets("day", date, tz) do
    for hour <- Readings.hours(date, tz) do
      local = hour.hour |> DateTime.from_unix!() |> DateTime.shift_zone!(tz)
      next = local |> DateTime.add(3600) |> Calendar.strftime("%H:00")
      Map.put(hour, :title, "#{Calendar.strftime(local, "%H:00")} – #{next}")
    end
  end

  defp buckets("year", date, tz) do
    for month <- Readings.months(date.year, tz) do
      Map.put(month, :title, "#{String.capitalize(month(month.month))} #{month.month.year}")
    end
  end

  defp buckets(period, first, tz) do
    last = shift(period, first, 1) |> Date.add(-1)

    for day <- Readings.days(first, last, tz) do
      Map.put(day, :title, String.capitalize(day_month(day.date)))
    end
  end

  defp future?(%{hour: hour}, _today), do: hour > System.os_time(:second)
  defp future?(%{month: month}, today), do: Date.compare(month, today) == :gt
  defp future?(%{date: date}, today), do: Date.compare(date, today) == :gt

  # Where now falls in a running period, in bars from the left.
  defp now_position("day", [first | _], _tz), do: (System.os_time(:second) - first.hour) / 3600

  defp now_position("year", _months, tz) do
    local = DateTime.now!(tz)
    local.month - 1 + (local.day - 1) / Date.days_in_month(local)
  end

  defp now_position(_period, [first | _], tz) do
    local = DateTime.now!(tz)
    seconds = local.hour * 3600 + local.minute * 60 + local.second
    Date.diff(DateTime.to_date(local), first.date) + seconds / 86_400
  end

  defp title("day", first),
    do: "#{String.capitalize(day_month(first))} #{first.year}"

  defp title("week", first) do
    {_, week} = :calendar.iso_week_number(Date.to_erl(first))
    last = Date.add(first, 6)

    from =
      if first.month == last.month, do: "#{first.day}", else: "#{first.day} #{month(first)}"

    "Week #{week} · #{from} – #{last.day} #{month(last)} #{last.year}"
  end

  defp title("month", first), do: "#{String.capitalize(month(first))} #{first.year}"
  defp title("year", first), do: "#{first.year}"

  defp names("day", first, today) do
    if first == today,
      do: {"Vandaag", "Gisteren", "gisteren"},
      else: {"Deze dag", "Dag ervoor", "de dag ervoor"}
  end

  defp names("week", _first, _today), do: {"Deze week", "Vorige week", "vorige week"}
  defp names("month", _first, _today), do: {"Deze maand", "Vorige maand", "vorige maand"}
  defp names("year", _first, _today), do: {"Dit jaar", "Vorig jaar", "vorig jaar"}

  defp compare_note(previous, true), do: "#{previous} op hetzelfde moment"
  defp compare_note(previous, false), do: previous

  defp per("day"), do: "uur"
  defp per("year"), do: "maand"
  defp per(_period), do: "dag"

  defp ticks("day", _bars), do: ~w(00:00 04:00 08:00 12:00 16:00 20:00 24:00)
  defp ticks("week", bars), do: Enum.map(bars, &weekday_day(&1.date))
  defp ticks("year", _bars), do: ~w(jan feb mrt apr mei jun jul aug sep okt nov dec)

  defp ticks("month", bars) do
    for {day, i} <- Enum.with_index(bars), rem(i, 7) == 0, do: "#{day.date.day}"
  end

  defp ticks_narrow("day", _bars), do: ~w(00 06 12 18 24)
  defp ticks_narrow("year", _bars), do: ~w(jan apr jul okt)
  defp ticks_narrow(period, bars), do: ticks(period, bars)

  defp electricity(usage),
    do:
      Enum.map(
        usage,
        &%{title: &1.title, up: &1.delivered_wh, down: &1.returned_wh, cost: &1.cost}
      )

  defp gas(usage), do: Enum.map(usage, &%{title: &1.title, up: &1.gas_l})

  # The gas peak label names the hour for a day, else the bar's title.
  defp gas_bars("day", usage) do
    for u <- usage, do: %{title: String.slice(u.title, 0, 5), up: u.gas_l}
  end

  defp gas_bars(_period, usage), do: gas(usage)

  @impl true
  def render(assigns) do
    {current, previous, phrase} = names(assigns.period, assigns.first, assigns.today)

    assigns =
      assign(assigns,
        current_name: current,
        previous_name: previous,
        phrase: phrase,
        max_wh: assigns.current |> Enum.map(& &1.delivered_wh) |> Enum.max(fn -> 0 end),
        max_gas: assigns.current |> Enum.map(& &1.gas_l) |> Enum.max(fn -> 0 end)
      )

    ~H"""
    <Layouts.app flash={@flash} active={:history}>
      <div class="flex items-center justify-between gap-3">
        <nav
          aria-label="Periode"
          class="flex flex-1 gap-0.5 rounded-full border border-tile-line bg-tile p-1 text-sm font-semibold backdrop-blur-xl sm:flex-none"
        >
          <.link
            :for={
              {p, label} <- [{"day", "Dag"}, {"week", "Week"}, {"month", "Maand"}, {"year", "Jaar"}]
            }
            id={"period-#{p}"}
            patch={history_path(p, @first)}
            aria-current={p == @period && "page"}
            class={[
              "flex-1 rounded-full py-3 text-center transition-colors duration-200 sm:flex-none sm:px-[18px] sm:py-2.5",
              if(p == @period,
                do: "bg-inverse text-on-inverse",
                else: "text-muted hover:text-ink"
              )
            ]}
          >
            {label}
          </.link>
        </nav>
        <div class="flex shrink-0 gap-2">
          <.link
            id="previous-period"
            patch={history_path(@period, shift(@period, @first, -1))}
            class="grid size-11 place-items-center rounded-full border border-tile-line bg-tile backdrop-blur-xl transition hover:-translate-x-px"
            aria-label={"Vorige #{period_name(@period)}"}
          >
            <.icon name="hero-chevron-left-mini" class="size-5" />
          </.link>
          <.link
            :if={@next?}
            id="next-period"
            patch={history_path(@period, shift(@period, @first, 1))}
            class="grid size-11 place-items-center rounded-full border border-tile-line bg-tile backdrop-blur-xl transition hover:translate-x-px"
            aria-label={"Volgende #{period_name(@period)}"}
          >
            <.icon name="hero-chevron-right-mini" class="size-5" />
          </.link>
          <span
            :if={!@next?}
            class="grid size-11 place-items-center rounded-full border border-tile-line bg-tile text-subtle opacity-50"
            aria-hidden="true"
          >
            <.icon name="hero-chevron-right-mini" class="size-5" />
          </span>
        </div>
      </div>

      <header class="mt-1 flex flex-col gap-1.5 sm:mt-2.5">
        <h1
          id="period-title"
          class="text-[28px] font-bold leading-[1.1] tracking-[-0.025em] sm:text-4xl"
        >
          {title(@period, @first)}
        </h1>
        <p class="text-[15px] text-muted text-pretty">
          Lichte balken tonen {String.downcase(@previous_name)}. Verschillen zijn ten opzichte van {compare_note(
            @phrase,
            @partial?
          )}. Tik op een balk voor details.
        </p>
      </header>

      <dl id="totals" class="grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
        <.total
          id="total-electricity"
          dot="bg-use"
          label="Elektriciteit"
          value={kwh(@totals.delivered_wh)}
          unit="kWh"
          now={@totals.delivered_wh}
          before={@previous_totals.delivered_wh}
        />
        <.total
          id="total-returned"
          dot="bg-return"
          label="Teruggeleverd"
          value={kwh(@totals.returned_wh)}
          unit="kWh"
          now={@totals.returned_wh}
          before={@previous_totals.returned_wh}
          more_is_better
        />
        <.total
          id="total-gas"
          dot="bg-gas"
          label="Gas"
          value={m3(@totals.gas_l)}
          unit="m³"
          now={@totals.gas_l}
          before={@previous_totals.gas_l}
        />
        <.total
          id="total-cost"
          dot="bg-cost"
          label="Kosten"
          value={if @totals.cost, do: euro(@totals.cost), else: "—"}
          now={@totals.cost}
          before={@previous_totals.cost}
        />
      </dl>

      <.card class="gap-3 px-[18px] py-[22px] sm:px-6">
        <:title><span class="text-lg">Elektriciteit</span></:title>
        <:aside>max {kwh(@max_wh)} kWh</:aside>
        <.legend>
          <:item color="bg-use">Afname</:item>
          <:item color="bg-return">Teruglevering</:item>
          <:item :if={@totals.cost} color="bg-cost" line>Kosten per {per(@period)}</:item>
          <:item color="bg-ink/14">{@previous_name}</:item>
        </.legend>
        <.period_bars
          id="history-electricity"
          label={"Elektriciteit per #{per(@period)}"}
          unit={:kwh}
          bars={electricity(@current)}
          compare={electricity(@previous)}
          current={@current_name}
          previous={@previous_name}
          cost={@totals.cost != nil}
          now={@now}
          ticks={ticks(@period, @current)}
          ticks_narrow={ticks_narrow(@period, @current)}
        />
      </.card>

      <.card class="gap-3 px-[18px] py-[22px] sm:px-6">
        <:title><span class="text-lg">Gas</span></:title>
        <:aside>max {m3(@max_gas)} m³</:aside>
        <.legend>
          <:item color="bg-gas">{@current_name}</:item>
          <:item color="bg-ink/14">{@previous_name}</:item>
        </.legend>
        <.period_bars
          id="history-gas"
          label={"Gas per #{per(@period)}"}
          unit={:m3}
          color={:gas}
          class="h-[170px] sm:h-[220px]"
          bars={gas_bars(@period, @current)}
          compare={gas(@previous)}
          current={@current_name}
          previous={@previous_name}
          now={@now}
          peak
          ticks={ticks(@period, @current)}
          ticks_narrow={ticks_narrow(@period, @current)}
        />
      </.card>
    </Layouts.app>
    """
  end

  defp period_name("day"), do: "dag"
  defp period_name("week"), do: "week"
  defp period_name("month"), do: "maand"
  defp period_name("year"), do: "jaar"

  slot :item, required: true do
    attr :color, :string, required: true
    attr :line, :boolean
  end

  defp legend(assigns) do
    ~H"""
    <p class="flex flex-wrap gap-x-3.5 gap-y-1 text-xs text-muted">
      <span :for={item <- @item} class="flex items-center gap-1.5">
        <span class={[
          item.color,
          if(item[:line], do: "h-0.5 w-3.5 rounded-px", else: "size-2.5 rounded-[3px]")
        ]} />
        {render_slot(item)}
      </span>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :dot, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, default: nil
  attr :now, :any, required: true
  attr :before, :any, required: true
  attr :more_is_better, :boolean, default: false

  defp total(assigns) do
    change =
      if is_number(assigns.now) and is_number(assigns.before) and assigns.before > 0,
        do: round((assigns.now - assigns.before) / assigns.before * 100)

    assigns = assign(assigns, change: change)

    ~H"""
    <.stat id={@id} dot={@dot} label={@label} value={@value} unit={@unit}>
      <:note :if={@change}>
        <span class={[
          "font-mono text-xs",
          cond do
            @change == 0 -> "text-subtle"
            @change > 0 == @more_is_better -> "text-return-ink"
            true -> "text-use-ink"
          end
        ]}>
          {if @change > 0, do: "+", else: if(@change < 0, do: "−")}{abs(@change)}%
        </span>
      </:note>
    </.stat>
    """
  end
end
