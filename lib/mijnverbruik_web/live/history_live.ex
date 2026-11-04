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
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "History")}

  @impl true
  def handle_params(params, _uri, socket) do
    tz = Application.fetch_env!(:mijnverbruik, :timezone)
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

    {:noreply,
     assign(socket,
       period: period,
       first: first,
       today: today,
       current: current,
       previous: previous,
       totals: Readings.total(current),
       previous_totals: previous |> Enum.take(elapsed) |> Readings.total(),
       partial?: elapsed < length(current),
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
      Map.put(hour, :label, Calendar.strftime(local, "%H:00"))
    end
  end

  defp buckets("year", date, tz) do
    for month <- Readings.months(date.year, tz) do
      Map.put(month, :label, Calendar.strftime(month.month, "%b"))
    end
  end

  defp buckets(period, first, tz) do
    last = shift(period, first, 1) |> Date.add(-1)

    for day <- Readings.days(first, last, tz) do
      format = if period == "week", do: "%a %-d", else: "%-d %b"
      Map.put(day, :label, Calendar.strftime(day.date, format))
    end
  end

  defp future?(%{hour: hour}, _today), do: hour > System.os_time(:second)
  defp future?(%{month: month}, today), do: Date.compare(month, today) == :gt
  defp future?(%{date: date}, today), do: Date.compare(date, today) == :gt

  defp title("day", first), do: Calendar.strftime(first, "%A %-d %B %Y")

  defp title("week", first) do
    {_, week} = :calendar.iso_week_number(Date.to_erl(first))
    last = Date.add(first, 6)

    "Week #{week} · #{Calendar.strftime(first, "%-d %b")} – #{Calendar.strftime(last, "%-d %b %Y")}"
  end

  defp title("month", first), do: Calendar.strftime(first, "%B %Y")
  defp title("year", first), do: "#{first.year}"

  defp compare_label("day", partial?),
    do: if(partial?, do: "vs yesterday at this time", else: "vs the day before")

  defp compare_label(period, true), do: "vs the same point last #{period}"
  defp compare_label(period, false), do: "vs the #{period} before"

  defp electricity(usage),
    do: Enum.map(usage, &%{label: &1.label, up: &1.delivered_wh, down: &1.returned_wh})

  defp gas(usage), do: Enum.map(usage, &%{label: &1.label, up: &1.gas_l})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:history}>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <nav aria-label="Period" class="inline-flex rounded-full bg-base-200 p-1 text-sm">
          <.link
            :for={p <- ~w(day week month year)}
            id={"period-#{p}"}
            patch={history_path(p, @first)}
            aria-current={p == @period && "page"}
            class={[
              "rounded-full px-3 py-1 capitalize transition-colors",
              if(p == @period,
                do: "bg-base-100 shadow-sm",
                else: "text-base-content/60 hover:text-base-content"
              )
            ]}
          >
            {p}
          </.link>
        </nav>
        <div class="flex items-center gap-1">
          <.link
            id="previous-period"
            patch={history_path(@period, shift(@period, @first, -1))}
            class="btn btn-ghost btn-sm btn-circle"
            aria-label={"Previous #{@period}"}
          >
            <.icon name="hero-chevron-left" class="size-4" />
          </.link>
          <.link
            :if={@next?}
            id="next-period"
            patch={history_path(@period, shift(@period, @first, 1))}
            class="btn btn-ghost btn-sm btn-circle"
            aria-label={"Next #{@period}"}
          >
            <.icon name="hero-chevron-right" class="size-4" />
          </.link>
          <span :if={!@next?} class="btn btn-ghost btn-sm btn-circle btn-disabled" aria-hidden="true">
            <.icon name="hero-chevron-right" class="size-4" />
          </span>
        </div>
      </div>

      <h1 id="period-title" class="mt-6 text-2xl font-semibold">{title(@period, @first)}</h1>
      <p class="text-sm text-base-content/60">
        Light bars show the {@period} before; changes are {compare_label(@period, @partial?)}.
      </p>

      <dl id="totals" class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <.total
          id="total-electricity"
          label="Electricity used"
          value={"#{kwh(@totals.delivered_wh)} kWh"}
          now={@totals.delivered_wh}
          before={@previous_totals.delivered_wh}
        />
        <.total
          id="total-returned"
          label="Returned"
          value={"#{kwh(@totals.returned_wh)} kWh"}
          now={@totals.returned_wh}
          before={@previous_totals.returned_wh}
          more_is_better
        />
        <.total
          id="total-gas"
          label="Gas"
          value={"#{m3(@totals.gas_l)} m³"}
          now={@totals.gas_l}
          before={@previous_totals.gas_l}
        />
        <.total
          id="total-cost"
          label="Costs"
          value={if @totals.cost, do: euro(@totals.cost), else: "—"}
          now={@totals.cost}
          before={@previous_totals.cost}
        />
      </dl>

      <.bars
        id="history-electricity"
        title="Electricity"
        unit={:kwh}
        bars={electricity(@current)}
        compare={electricity(@previous)}
      />
      <.bars
        id="history-gas"
        title="Gas"
        unit={:m3}
        bars={gas(@current)}
        compare={gas(@previous)}
      />
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :now, :any, required: true
  attr :before, :any, required: true
  attr :more_is_better, :boolean, default: false

  defp total(assigns) do
    change =
      if is_number(assigns.now) and is_number(assigns.before) and assigns.before > 0,
        do: round((assigns.now - assigns.before) / assigns.before * 100)

    assigns = assign(assigns, change: change)

    ~H"""
    <div id={@id} class="rounded-xl border border-base-300 p-3">
      <dt class="text-xs text-base-content/60">{@label}</dt>
      <dd class="text-xl font-medium tabular-nums">{@value}</dd>
      <dd
        :if={@change}
        class={[
          "text-xs tabular-nums",
          cond do
            @change == 0 -> "text-base-content/60"
            @change > 0 == @more_is_better -> "text-success"
            true -> "text-warning"
          end
        ]}
      >
        {if @change > 0, do: "+"}{@change}%
      </dd>
    </div>
    """
  end
end
