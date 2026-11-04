defmodule MijnverbruikWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts.
  """
  use Phoenix.Component

  import MijnverbruikWeb.Format

  @height 40

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :unit, :atom, values: [:kwh, :m3, :eur_kwh], required: true
  attr :class, :any, default: "mt-10"

  attr :highlight, :integer,
    default: nil,
    doc: "index of a bar to emphasise, e.g. the current hour"

  attr :bars, :list, required: true, doc: "maps with :label, :up and optional :down"

  attr :compare, :list,
    default: nil,
    doc: "maps with :up and optional :down, drawn as ghost bars behind `bars` by position"

  @doc """
  Bar chart with usage going up from the zero line and, when any bar has a
  `:down` value, return going down from it. Values are Wh for `:kwh`,
  litres for `:m3` and euros for `:eur_kwh`.

  Hovering or tapping a bar shows its value above the chart.
  """
  def bars(assigns) do
    all = assigns.bars ++ (assigns.compare || [])
    up_max = all |> Enum.map(& &1.up) |> Enum.max(fn -> 0 end)
    down_max = all |> Enum.map(&Map.get(&1, :down, 0)) |> Enum.max(fn -> 0 end)
    scale = if up_max + down_max > 0, do: @height / (up_max + down_max), else: 0
    zero = up_max * scale
    count = length(assigns.bars)

    assigns =
      assign(assigns,
        ghosts: Enum.with_index(assigns.compare || []),
        down_max: down_max,
        scale: scale,
        zero: zero,
        width: 100 / max(count, 1),
        height: @height,
        grid: for(v <- gridlines(up_max), do: {v, (zero - v * scale) / @height * 100}),
        ticks: ticks(assigns.bars),
        summary: summary(up_max, down_max, assigns.unit)
      )

    ~H"""
    <section
      id={"#{@id}-chart"}
      aria-labelledby={"#{@id}-title"}
      class={["space-y-3", @class]}
      phx-hook=".BarReadout"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-x-3">
        <h2 id={"#{@id}-title"} class="text-sm font-medium text-base-content/60">{@title}</h2>
        <p
          id={"#{@id}-readout"}
          class="text-xs tabular-nums text-base-content/60"
          aria-live="polite"
          data-readout
          data-default={@summary}
        >
          {@summary}
        </p>
      </div>
      <div class="relative">
        <svg
          id={@id}
          viewBox={"0 0 100 #{@height}"}
          preserveAspectRatio="none"
          class="h-40 w-full touch-pan-y"
          role="img"
          aria-label={"#{@title}, per bar in #{unit(@unit)}"}
        >
          <line
            :for={{_value, y} <- @grid}
            x1="0"
            x2="100"
            y1={y / 100 * @height}
            y2={y / 100 * @height}
            class="stroke-base-content/10"
            stroke-width="1"
            stroke-dasharray="2 3"
            vector-effect="non-scaling-stroke"
          />
          <line
            x1="0"
            x2="100"
            y1={@zero}
            y2={@zero}
            class="stroke-base-content/20"
            stroke-width="1"
            vector-effect="non-scaling-stroke"
          />
          <g :for={{bar, i} <- @ghosts} class="fill-base-content/10" aria-hidden="true">
            <rect
              x={i * @width + @width * 0.02}
              y={@zero - bar.up * @scale}
              width={@width * 0.96}
              height={bar.up * @scale}
              rx="0.5"
            />
            <rect
              :if={Map.get(bar, :down, 0) > 0}
              x={i * @width + @width * 0.02}
              y={@zero}
              width={@width * 0.96}
              height={bar.down * @scale}
              rx="0.5"
            />
          </g>
          <g
            :for={{bar, i} <- Enum.with_index(@bars)}
            data-bar={bar_title(bar, @unit)}
            class={["transition-opacity", @highlight && @highlight != i && "opacity-40"]}
          >
            <title>{bar_title(bar, @unit)}</title>
            <rect
              x={i * @width}
              y="0"
              width={@width}
              height={@height}
              fill="transparent"
            />
            <rect
              x={i * @width + @width * 0.1}
              y={@zero - bar.up * @scale}
              width={@width * 0.8}
              height={bar.up * @scale}
              class="fill-primary"
              rx="0.5"
            />
            <rect
              :if={Map.get(bar, :down, 0) > 0}
              x={i * @width + @width * 0.1}
              y={@zero}
              width={@width * 0.8}
              height={bar.down * @scale}
              class="fill-success"
              rx="0.5"
            />
          </g>
        </svg>
        <span
          :for={{value, top} <- @grid}
          class="pointer-events-none absolute left-0 -translate-y-full pb-0.5 text-[10px] tabular-nums text-base-content/50"
          style={"top: #{top}%"}
          aria-hidden="true"
        >
          {value(value, @unit)}
        </span>
      </div>
      <div class="relative h-4 text-xs text-base-content/60" aria-hidden="true">
        <span
          :for={{label, i} <- @ticks}
          class={["absolute whitespace-nowrap", i > 0 && "-translate-x-1/2"]}
          style={"left: #{if i == 0, do: 0, else: (i + 0.5) * @width}%"}
        >
          {label}
        </span>
      </div>
      <p :if={@down_max > 0 and @unit != :eur_kwh} class="flex gap-4 text-xs text-base-content/60">
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-primary"></span>Used
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-success"></span>Returned
        </span>
        <span :if={@compare} class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-base-content/10"></span>Period before
        </span>
      </p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".BarReadout">
        export default {
          mounted() {
            this.active = null
            const pick = (e) => {
              const bar = e.target.closest("[data-bar]")
              if (!bar) return
              this.active = [...this.el.querySelectorAll("[data-bar]")].indexOf(bar)
              this.render()
            }
            this.el.addEventListener("pointerover", pick)
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
            readout.textContent = active ? active.dataset.bar : readout.dataset.default
            readout.classList.toggle("text-base-content", !!active)
            bars.forEach((bar) => { bar.style.opacity = !active ? "" : bar === active ? "1" : "0.4" })
          }
        }
      </script>
    </section>
    """
  end

  # Two or three round values between zero and `max`.
  defp gridlines(max) when max <= 0, do: []

  defp gridlines(max) do
    raw = max / 3
    magnitude = :math.pow(10, :math.floor(:math.log10(raw)))
    step = Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= raw)) * magnitude

    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&(&1 * step))
    |> Enum.take_while(&(&1 <= max))
  end

  # At most six evenly spaced labels, on steps that suit hours, days and months.
  defp ticks(bars) do
    count = length(bars)
    step = Enum.find([1, 2, 3, 4, 6, 7, 12, 24], 24, &(ceil(count / &1) <= 6))

    for {bar, i} <- Enum.with_index(bars), rem(i, step) == 0, do: {bar.label, i}
  end

  defp summary(up_max, down_max, :eur_kwh) when down_max > 0,
    do: "max #{value(up_max, :eur_kwh)} · lowest #{value(-down_max, :eur_kwh)}"

  defp summary(up_max, down_max, unit) when down_max > 0,
    do: "max #{value(up_max, unit)} · returned max #{value(down_max, unit)}"

  defp summary(up_max, _down_max, unit), do: "max #{value(up_max, unit)}"

  attr :id, :string, required: true
  attr :samples, :list, required: true, doc: "`{unix_seconds, watts}` tuples, oldest first"
  attr :now, :integer, required: true
  attr :window, :integer, required: true, doc: "seconds shown, ending at `now`"

  @doc """
  Line chart of net power over the last `window` seconds. Return (negative
  power) falls below the zero line. Gaps over 5 seconds break the line.
  """
  def trend(assigns) do
    watts = Enum.map(assigns.samples, &elem(&1, 1))
    top = max(Enum.max(watts, fn -> 0 end), 100)
    bottom = min(Enum.min(watts, fn -> 0 end), 0)
    y = fn w -> (top - w) / (top - bottom) * @height end
    x = fn t -> (t - (assigns.now - assigns.window)) / assigns.window * 100 end

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
        points = Enum.map(segment, fn {t, w} -> "#{fmt(x.(t))},#{fmt(y.(w))}" end)
        {first_t, _} = hd(segment)
        {last_t, _} = List.last(segment)
        zero = fmt(y.(0))

        %{
          line: "M" <> Enum.join(points, "L"),
          area:
            "M#{fmt(x.(first_t))},#{zero}L" <>
              Enum.join(points, "L") <> "L#{fmt(x.(last_t))},#{zero}Z"
        }
      end)

    assigns = assign(assigns, paths: paths, zero: y.(0), height: @height, top: top)

    ~H"""
    <figure class="space-y-1">
      <svg
        id={@id}
        viewBox={"0 0 100 #{@height}"}
        preserveAspectRatio="none"
        class="h-24 w-full overflow-visible"
        role="img"
        aria-label={"Power over the last #{div(@window, 60)} minutes"}
      >
        <line
          x1="0"
          x2="100"
          y1={@zero}
          y2={@zero}
          class="stroke-base-content/20"
          stroke-width="1"
          vector-effect="non-scaling-stroke"
        />
        <defs>
          <clipPath id={"#{@id}-use"}>
            <rect x="0" y="0" width="100" height={@zero} />
          </clipPath>
          <clipPath id={"#{@id}-return"}>
            <rect x="0" y={@zero} width="100" height={@height - @zero} />
          </clipPath>
        </defs>
        <g
          :for={
            {clip, fill, stroke} <- [
              {"use", "fill-primary/15", "stroke-primary"},
              {"return", "fill-success/15", "stroke-success"}
            ]
          }
          clip-path={"url(##{@id}-#{clip})"}
        >
          <g :for={path <- @paths}>
            <path d={path.area} class={fill} />
            <path
              d={path.line}
              class={["fill-none", stroke]}
              stroke-width="1.5"
              stroke-linejoin="round"
              vector-effect="non-scaling-stroke"
            />
          </g>
        </g>
      </svg>
      <figcaption class="flex justify-between text-xs text-base-content/60">
        <span>{div(@window, 60)} min ago</span>
        <span class="tabular-nums">peak {@top} W</span>
        <span>now</span>
      </figcaption>
    </figure>
    """
  end

  defp fmt(n), do: :erlang.float_to_binary(n / 1, decimals: 2)

  defp bar_title(bar, :eur_kwh),
    do: "#{bar.label}: #{value(bar.up - Map.get(bar, :down, 0), :eur_kwh)}"

  defp bar_title(%{down: down} = bar, unit) when down > 0,
    do: "#{bar.label}: #{value(bar.up, unit)} used, #{value(down, unit)} returned"

  defp bar_title(bar, unit), do: "#{bar.label}: #{value(bar.up, unit)}"

  defp value(v, :kwh), do: "#{kwh(v)} kWh"
  defp value(v, :m3), do: "#{m3(v)} m³"
  defp value(v, :eur_kwh), do: "€#{:erlang.float_to_binary(v / 1, decimals: 3)}/kWh"

  defp unit(:kwh), do: "kWh"
  defp unit(:m3), do: "m³"
  defp unit(:eur_kwh), do: "€/kWh"
end
