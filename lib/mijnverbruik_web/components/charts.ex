defmodule MijnverbruikWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts. They fill the height of their container, so a
  card decides how tall a chart is.
  """
  use Phoenix.Component

  import MijnverbruikWeb.Format

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "what the chart shows, for screen readers"
  attr :unit, :atom, values: [:kwh, :m3, :eur_kwh, :w], required: true
  attr :class, :any, default: "h-40"

  attr :bars, :list,
    required: true,
    doc: """
    maps with `:label`, `:up` and optional `:down` (drawn below the zero line)
    and `:tone` (`:past`, `:now`, `:cheap` or `:future`, for prices); `:up` is
    nil for a bar without data
    """

  attr :color, :atom,
    values: [:use, :gas],
    default: :use,
    doc: "the colour of bars going up; bars going down are always return"

  attr :compare, :list,
    default: nil,
    doc: "maps with `:up` and optional `:down`, drawn as ghost bars behind `bars` by position"

  attr :ticks, :list,
    default: nil,
    doc: "x-axis labels, spread evenly; by default up to six bar labels"

  @doc """
  Bar chart with use going up from the zero line and, when any bar has a
  `:down` value, return going down from it. Values are Wh for `:kwh`, litres
  for `:m3`, euros for `:eur_kwh` and watts for `:w`.

  Hovering, tapping or dragging over the chart shows a bar's value.
  """
  def bars(assigns) do
    all = Enum.reject(assigns.bars ++ (assigns.compare || []), &is_nil(&1.up))
    up_max = all |> Enum.map(& &1.up) |> Enum.max(fn -> 0 end) |> max(0)
    down_max = all |> Enum.map(&Map.get(&1, :down, 0)) |> Enum.max(fn -> 0 end) |> max(0)
    total = up_max + down_max
    scale = if total > 0, do: 100 / total, else: 0
    zero = if total > 0, do: up_max * scale, else: 100

    assigns =
      assign(assigns,
        count: max(length(assigns.bars), 1),
        scale: scale,
        zero: zero,
        ghosts: Enum.with_index(assigns.compare || []),
        ticks: assigns.ticks || default_ticks(assigns.bars)
      )

    ~H"""
    <figure
      id={"#{@id}-chart"}
      class={["relative flex min-h-0 flex-col gap-2.5", @class]}
      phx-hook=".ChartReadout"
    >
      <figcaption
        class="pointer-events-none absolute -top-1 right-0 z-10 rounded-full bg-inverse px-2.5 py-1 font-mono text-[11px] text-on-inverse opacity-0 shadow-float transition-opacity duration-150 data-active:opacity-100"
        aria-live="polite"
        data-readout
      />
      <svg
        id={@id}
        viewBox={"0 0 #{@count} 100"}
        preserveAspectRatio="none"
        class="block h-0 min-h-0 w-full flex-1 touch-pan-y overflow-visible"
        role="img"
        aria-label={@label}
      >
        <g :for={{bar, i} <- @ghosts} class="fill-ink/10" aria-hidden="true">
          <rect
            :if={(bar.up || 0) > 0}
            x={fmt(i + 0.1)}
            y={fmt(@zero - bar.up * @scale)}
            width="0.8"
            height={fmt(bar.up * @scale)}
          />
          <rect
            :if={Map.get(bar, :down, 0) > 0}
            x={fmt(i + 0.1)}
            y={fmt(@zero)}
            width="0.8"
            height={fmt(bar.down * @scale)}
          />
        </g>
        <g
          :for={{bar, i} <- Enum.with_index(@bars)}
          data-bar={bar_title(bar, @unit)}
          class="transition-opacity duration-150"
        >
          <rect
            :if={(bar.up || 0) > 0}
            x={fmt(i + 0.15)}
            y={fmt(@zero - bar.up * @scale)}
            width="0.7"
            height={fmt(bar.up * @scale)}
            class={up_class(bar, @color)}
          />
          <rect
            :if={Map.get(bar, :down, 0) > 0}
            x={fmt(i + 0.15)}
            y={fmt(@zero)}
            width="0.7"
            height={fmt(bar.down * @scale)}
            class="fill-return"
          />
        </g>
        <line
          :if={@zero < 100}
          x1="0"
          x2={@count}
          y1={fmt(@zero)}
          y2={fmt(@zero)}
          class="stroke-ink/60"
          stroke-width="1"
          vector-effect="non-scaling-stroke"
        />
      </svg>
      <div class="flex justify-between font-mono text-[11px] text-subtle" aria-hidden="true">
        <span :for={tick <- @ticks}>{tick}</span>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChartReadout">
        export default {
          mounted() {
            this.active = null
            // By position, so a finger can drag along the chart.
            const pick = (e) => {
              const svg = this.el.querySelector("svg")
              const { left, width } = svg.getBoundingClientRect()
              const count = this.el.querySelectorAll("[data-bar]").length
              const i = Math.floor(((e.clientX - left) / width) * count)
              this.active = Math.min(Math.max(i, 0), count - 1)
              this.render()
            }
            this.el.addEventListener("pointermove", pick)
            this.el.addEventListener("pointerdown", pick)
            this.el.addEventListener("pointerleave", (e) => {
              if (e.pointerType === "mouse") { this.active = null; this.render() }
            })
          },
          updated() { this.render() },
          render() {
            const readout = this.el.querySelector("[data-readout]")
            const bars = [...this.el.querySelectorAll("[data-bar]")]
            const active = bars[this.active]
            if (active) readout.textContent = active.dataset.bar
            readout.toggleAttribute("data-active", !!active)
            bars.forEach((bar) => {
              bar.style.opacity = !active || bar === active ? "" : "0.35"
            })
          }
        }
      </script>
    </figure>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "what the chart shows, for screen readers"
  attr :unit, :atom, values: [:kwh, :m3], required: true
  attr :color, :atom, values: [:use, :gas], default: :use
  attr :class, :any, default: "h-[230px] sm:h-[300px]"

  attr :bars, :list,
    required: true,
    doc: """
    maps with `:title` (for the tooltip), `:up`, optional `:down` and, to draw
    the cost line, `:cost` in euros (nil where unknown)
    """

  attr :compare, :list, required: true, doc: "maps with `:up` and optional `:down`, by position"
  attr :current, :string, required: true, doc: "the name of this period, e.g. \"Vandaag\""
  attr :previous, :string, required: true, doc: "the name of the period before, e.g. \"Gisteren\""
  attr :cost, :boolean, default: false, doc: "draws the cost per bar as a line, on its own axis"
  attr :now, :any, default: nil, doc: "where now falls, in bars from the left, or nil"
  attr :peak, :boolean, default: false, doc: "labels the highest bar"
  attr :ticks, :list, required: true, doc: "x-axis labels, spread evenly"
  attr :ticks_narrow, :list, default: nil, doc: "fewer x-axis labels for phones"

  @doc """
  Bars for a period of history, with the period before as wider ghost bars
  behind them, round gridlines and optionally the cost per bar as a line.
  Return goes below the zero line. Hovering or tapping a bar shows all its
  values in a tooltip.
  """
  def period_bars(assigns) do
    all = assigns.bars ++ assigns.compare
    up_max = all |> Enum.map(&(&1.up || 0)) |> Enum.max(fn -> 0 end)
    down_max = all |> Enum.map(&(Map.get(&1, :down) || 0)) |> Enum.max(fn -> 0 end)
    # Headroom above the highest bar, for the tooltip and peak label.
    top = up_max * 1.08
    total = top + down_max
    scale = if total > 0, do: 100 / total, else: 0
    zero = if total > 0, do: top * scale, else: 100
    costs = for bar <- assigns.bars, is_number(bar[:cost]), do: bar.cost
    cost_top = costs |> Enum.max(fn -> 0 end) |> nice_ceiling()
    count = max(length(assigns.bars), 1)

    cost_line =
      if assigns.cost and cost_top > 0 do
        assigns.bars
        |> Enum.with_index()
        |> Enum.filter(fn {bar, _i} -> is_number(bar[:cost]) end)
        |> Enum.map(fn {bar, i} ->
          "#{fmt(i + 0.5)} #{fmt(100 - max(bar.cost, 0) / cost_top * 96)}"
        end)
        |> then(fn points -> if points == [], do: nil, else: "M" <> Enum.join(points, " L") end)
      end

    peak =
      if assigns.peak do
        assigns.bars
        |> Enum.with_index()
        |> Enum.filter(fn {bar, _} -> (bar.up || 0) > 0 end)
        |> Enum.max_by(fn {bar, _} -> bar.up end, fn -> nil end)
      end

    assigns =
      assign(assigns,
        count: count,
        scale: scale,
        zero: zero,
        grid: for(v <- gridlines(up_max), do: {value(v, assigns.unit), zero - v * scale}),
        cost_top: cost_top,
        cost_line: cost_line,
        peak_bar: peak,
        rows: Enum.zip(assigns.bars, pad(assigns.compare, length(assigns.bars)))
      )

    ~H"""
    <figure id={"#{@id}-chart"} class="flex flex-col gap-2.5" phx-hook=".PeriodTip">
      <div class={["relative mt-2", @class]}>
        <div
          :for={{label, top} <- @grid}
          class="absolute inset-x-0 border-t border-dashed border-ink/10"
          style={"top: #{fmt(top)}%"}
          aria-hidden="true"
        >
          <span class="absolute -top-4 left-0 font-mono text-[10px] text-subtle">{label}</span>
        </div>
        <div
          class="absolute inset-x-0 border-t border-ink/35"
          style={"top: #{fmt(@zero)}%"}
          aria-hidden="true"
        >
          <span class="absolute -top-4 left-0 font-mono text-[10px] text-subtle">0</span>
        </div>
        <span
          :if={@cost_line}
          class="absolute -top-4 right-0 font-mono text-[10px] text-cost-ink"
          aria-hidden="true"
        >
          {MijnverbruikWeb.Format.euro(@cost_top)}
        </span>
        <span
          :if={@cost_line}
          class="absolute right-0 top-[calc(50%-16px)] font-mono text-[10px] text-cost-ink"
          aria-hidden="true"
        >
          {MijnverbruikWeb.Format.euro(@cost_top / 2)}
        </span>

        <svg
          id={@id}
          viewBox={"0 0 #{@count} 100"}
          preserveAspectRatio="none"
          class="absolute inset-0 block size-full touch-pan-y overflow-visible"
          role="img"
          aria-label={@label}
        >
          <g
            :for={{{bar, ghost}, i} <- Enum.with_index(@rows)}
            data-bar
            data-tip={tip(bar, ghost, @unit, @current, @previous, @color)}
          >
            <rect
              x={i}
              y="0"
              width="1"
              height="100"
              class="fill-ink/7 opacity-0 transition-opacity"
              data-hover
            />
            <rect
              :if={(ghost.up || 0) > 0}
              x={fmt(i + 0.08)}
              y={fmt(@zero - ghost.up * @scale)}
              width="0.84"
              height={fmt(ghost.up * @scale)}
              class="fill-ink/14"
            />
            <rect
              :if={(Map.get(ghost, :down) || 0) > 0}
              x={fmt(i + 0.08)}
              y={fmt(@zero)}
              width="0.84"
              height={fmt(ghost.down * @scale)}
              class="fill-ink/14"
            />
            <rect
              :if={(bar.up || 0) > 0}
              x={fmt(i + 0.2)}
              y={fmt(@zero - bar.up * @scale)}
              width="0.6"
              height={fmt(bar.up * @scale)}
              class={if(@color == :gas, do: "fill-gas", else: "fill-use")}
            />
            <rect
              :if={(Map.get(bar, :down) || 0) > 0}
              x={fmt(i + 0.2)}
              y={fmt(@zero)}
              width="0.6"
              height={fmt(bar.down * @scale)}
              class="fill-return"
            />
          </g>
          <path
            :if={@cost_line}
            d={@cost_line}
            class="fill-none stroke-cost"
            stroke-width="2"
            stroke-linejoin="round"
            vector-effect="non-scaling-stroke"
          />
        </svg>

        <div
          :if={@now}
          class="pointer-events-none absolute -top-1 bottom-0 border-l-[1.5px] border-ink/55"
          style={"left: #{fmt(@now / @count * 100)}%"}
          aria-hidden="true"
        >
          <span class="absolute -top-0.5 left-1.5 font-mono text-[10px]">nu</span>
        </div>

        <div
          :if={@peak_bar}
          class="pointer-events-none absolute -translate-x-1/2 -translate-y-full whitespace-nowrap rounded-md bg-node px-1.5 py-0.5 font-mono text-[10px] text-gas"
          style={"left: #{fmt((elem(@peak_bar, 1) + 0.5) / @count * 100)}%; top: #{fmt(@zero - elem(@peak_bar, 0).up * @scale)}%"}
          aria-hidden="true"
        >
          piek {elem(@peak_bar, 0).title} · {MijnverbruikWeb.Format.m3(elem(@peak_bar, 0).up)}
        </div>

        <div
          data-tooltip
          role="status"
          aria-live="polite"
          class="pointer-events-none absolute z-10 hidden min-w-44 -translate-x-1/2 -translate-y-full flex-col gap-1.5 rounded-[14px] bg-inverse px-3.5 py-3 text-on-inverse shadow-float data-active:flex"
        />
      </div>
      <div class="hidden justify-between font-mono text-[11px] text-subtle sm:flex" aria-hidden="true">
        <span :for={tick <- @ticks}>{tick}</span>
      </div>
      <div class="flex justify-between font-mono text-[11px] text-subtle sm:hidden" aria-hidden="true">
        <span :for={tick <- @ticks_narrow || @ticks}>{tick}</span>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PeriodTip">
        export default {
          mounted() {
            this.active = null
            // By position, so a finger can drag along the chart.
            const pick = (e) => {
              const svg = this.el.querySelector("svg")
              const { left, width } = svg.getBoundingClientRect()
              const count = this.el.querySelectorAll("[data-bar]").length
              const i = Math.floor(((e.clientX - left) / width) * count)
              this.active = i >= 0 && i < count ? i : null
              this.render()
            }
            this.el.addEventListener("pointermove", pick)
            this.el.addEventListener("pointerdown", pick)
            this.el.addEventListener("pointerleave", (e) => {
              if (e.pointerType === "mouse") { this.active = null; this.render() }
            })
          },
          updated() { this.active = null; this.render() },
          render() {
            const tip = this.el.querySelector("[data-tooltip]")
            const bars = [...this.el.querySelectorAll("[data-bar]")]
            bars.forEach((bar, i) => {
              bar.querySelector("[data-hover]").style.opacity = i === this.active ? "1" : ""
            })
            const bar = bars[this.active]
            tip.toggleAttribute("data-active", !!bar)
            if (!bar) return
            const { title, rows } = JSON.parse(bar.dataset.tip)
            const head = document.createElement("p")
            head.className = "text-[13px] font-bold"
            head.textContent = title
            const lines = rows.map(([label, value, color]) => {
              const row = document.createElement("p")
              row.className = "flex justify-between gap-3 text-xs"
              const name = document.createElement("span")
              name.className = "flex items-center gap-1.5 opacity-80"
              const dot = document.createElement("span")
              dot.className = "size-[7px] rounded-[2px]"
              dot.style.background = color
              name.append(dot, label)
              const amount = document.createElement("span")
              amount.className = "font-mono"
              amount.textContent = value
              row.append(name, amount)
              return row
            })
            tip.replaceChildren(head, ...lines)
            // Above the bar's highest mark, kept inside the chart.
            const count = bars.length
            const x = Math.min(Math.max((this.active + 0.5) / count, 0.12), 0.88)
            const box = tip.parentElement.getBoundingClientRect()
            const marks = [...bar.querySelectorAll("rect:not([data-hover])")]
            const top = Math.min(box.height, ...marks.map((m) => m.getBoundingClientRect().top - box.top))
            tip.style.left = `${x * 100}%`
            tip.style.top = `${Math.max(top - 10, tip.offsetHeight)}px`
          }
        }
      </script>
    </figure>
    """
  end

  defp pad(list, n), do: Enum.take(list ++ List.duplicate(%{up: 0}, n), n)

  # The tooltip of one bar, as JSON for the hook.
  defp tip(bar, ghost, unit, current, previous, color) do
    rows =
      if color == :gas do
        [[current, value(bar.up || 0, unit), "var(--gas)"]]
      else
        [
          ["Afname", value(bar.up || 0, unit), "var(--use)"],
          ["Teruglevering", value(Map.get(bar, :down) || 0, unit), "var(--return)"]
        ] ++
          if(is_number(bar[:cost]),
            do: [["Kosten", MijnverbruikWeb.Format.euro(bar.cost), "var(--cost)"]],
            else: []
          )
      end

    Jason.encode!(%{
      title: bar.title,
      rows: rows ++ [[previous, value(ghost.up || 0, unit), "var(--subtle)"]]
    })
  end

  # A round number at or just above `max`, for the cost axis.
  defp nice_ceiling(max) when max <= 0, do: 0

  defp nice_ceiling(max) do
    magnitude = :math.pow(10, :math.floor(:math.log10(max)))
    Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= max)) * magnitude
  end

  # Two or three round values between zero and `max`.
  defp gridlines(max) when max <= 0, do: []

  defp gridlines(max) do
    raw = max / 2.5
    magnitude = :math.pow(10, :math.floor(:math.log10(raw)))
    step = Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= raw)) * magnitude

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&(&1 * step))
    |> Enum.take_while(&(&1 <= max))
  end

  defp up_class(%{tone: :past}, _color), do: "fill-ink/10"
  defp up_class(%{tone: :future}, _color), do: "fill-ink/28"
  defp up_class(%{tone: :now}, _color), do: "fill-ink"
  defp up_class(%{tone: :cheap}, _color), do: "fill-return"
  defp up_class(_bar, :gas), do: "fill-gas"
  defp up_class(_bar, :use), do: "fill-use"

  # Up to six evenly spaced bar labels.
  defp default_ticks([]), do: []

  defp default_ticks(bars) do
    count = length(bars)
    step = Enum.find([1, 2, 3, 4, 6, 7, 12, 24, 48], 48, &(ceil(count / &1) <= 6))
    for {bar, i} <- Enum.with_index(bars), rem(i, step) == 0, do: bar.label
  end

  attr :id, :string, required: true
  attr :samples, :list, required: true, doc: "`{unix_seconds, watts}` tuples, oldest first"
  attr :now, :integer, required: true
  attr :window, :integer, required: true, doc: "seconds shown, ending at `now`"
  attr :stale, :boolean, default: false, doc: "grey, for values that no longer describe now"
  attr :class, :any, default: "h-16"

  @doc """
  Line chart of net power over the last `window` seconds. Return (negative
  power) falls below the zero line. Gaps over 5 seconds break the line.
  """
  def trend(assigns) do
    watts = Enum.map(assigns.samples, &elem(&1, 1))
    top = Enum.max(watts, fn -> 0 end)
    bottom = Enum.min(watts, fn -> 0 end)
    # Some headroom, so the line does not hug the edges.
    hi = max(top, 100) * 1.1
    lo = if bottom < 0, do: bottom * 1.1, else: min(bottom * 0.8, hi * 0.5)
    y = fn w -> (hi - w) / (hi - lo) * 40 end
    x = fn t -> (t - (assigns.now - assigns.window)) / assigns.window * 60 end

    paths =
      assigns.samples
      |> Enum.chunk_while(
        [],
        fn
          {t, _} = s, [{prev, _} | _] = acc when t - prev > 5 -> {:cont, Enum.reverse(acc), [s]}
          s, acc -> {:cont, [s | acc]}
        end,
        fn
          [] -> {:cont, []}
          acc -> {:cont, Enum.reverse(acc), []}
        end
      )
      |> Enum.map(fn segment ->
        segment |> Enum.map(fn {t, w} -> {x.(t), y.(w)} end) |> area_paths(y.(max(lo, 0)))
      end)

    zero = y.(0)

    assigns =
      assign(assigns,
        paths: paths,
        zero: min(max(zero, 0), 40),
        minutes: div(assigns.window, 60)
      )

    ~H"""
    <figure class={["flex min-h-0 flex-col gap-2.5", @class]}>
      <svg
        id={@id}
        viewBox="0 0 60 40"
        preserveAspectRatio="none"
        class="block h-0 min-h-0 w-full flex-1 overflow-visible"
        role="img"
        aria-label={"Vermogen over de laatste #{@minutes} minuten"}
      >
        <defs>
          <clipPath id={"#{@id}-use"}><rect x="0" y="0" width="60" height={fmt(@zero)} /></clipPath>
          <clipPath id={"#{@id}-return"}>
            <rect x="0" y={fmt(@zero)} width="60" height={fmt(40 - @zero)} />
          </clipPath>
        </defs>
        <g
          :for={
            {clip, fill, stroke} <-
              if(@stale,
                do: [
                  {"use", "fill-stale/20", "stroke-stale"},
                  {"return", "fill-stale/20", "stroke-stale"}
                ],
                else: [
                  {"use", "fill-use/16", "stroke-use"},
                  {"return", "fill-return/16", "stroke-return"}
                ]
              )
          }
          clip-path={"url(##{@id}-#{clip})"}
        >
          <g :for={path <- @paths}>
            <path d={path.area} class={fill} />
            <path
              d={path.line}
              class={["fill-none", stroke]}
              stroke-width="2"
              stroke-linejoin="round"
              vector-effect="non-scaling-stroke"
            />
          </g>
        </g>
      </svg>
      <div class="flex justify-between font-mono text-[11px] text-subtle" aria-hidden="true">
        <span>−{@minutes} min</span>
        <span>nu</span>
      </div>
    </figure>
    """
  end

  defp area_paths(coords, base) do
    points = Enum.map(coords, fn {x, y} -> "#{fmt(x)},#{fmt(y)}" end)
    {first_x, _} = hd(coords)
    {last_x, _} = List.last(coords)

    %{
      line: "M" <> Enum.join(points, "L"),
      area:
        "M#{fmt(first_x)},#{fmt(base)}L" <>
          Enum.join(points, "L") <> "L#{fmt(last_x)},#{fmt(base)}Z"
    }
  end

  defp fmt(n), do: :erlang.float_to_binary(n / 1, decimals: 2)

  defp bar_title(%{up: nil} = bar, _unit), do: "#{bar.label}: geen data"

  defp bar_title(bar, :eur_kwh),
    do: "#{bar.label}: #{value(bar.up - Map.get(bar, :down, 0), :eur_kwh)}"

  defp bar_title(%{down: down} = bar, unit) when down > 0 and bar.up > 0,
    do: "#{bar.label}: #{value(bar.up, unit)} afgenomen, #{value(down, unit)} terug"

  defp bar_title(%{down: down} = bar, unit) when down > 0,
    do: "#{bar.label}: #{value(down, unit)} terug"

  defp bar_title(bar, unit), do: "#{bar.label}: #{value(bar.up, unit)}"

  @doc "A value with its unit, as the chart readouts show it."
  def value(v, :kwh), do: "#{kwh(v)} kWh"
  def value(v, :m3), do: "#{m3(v)} m³"
  def value(v, :eur_kwh), do: "#{euro_3(v)}/kWh"
  def value(v, :w), do: "#{watts(v)} W"

  defp euro_3(v) when v < 0, do: "−€ " <> decimal(-v, 3)
  defp euro_3(v), do: "€ " <> decimal(v, 3)
end
