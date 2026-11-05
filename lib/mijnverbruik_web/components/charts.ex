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

  Hovering, tapping or dragging over the chart shows a bar's value above it.
  """
  def bars(assigns) do
    all = assigns.bars ++ (assigns.compare || [])
    up_max = all |> Enum.map(& &1.up) |> Enum.max(fn -> 0 end)
    down_max = all |> Enum.map(&Map.get(&1, :down, 0)) |> Enum.max(fn -> 0 end)

    assigns =
      assigns
      |> assign_axes(assigns.bars, up_max, down_max, assigns.unit)
      |> assign(
        ghosts: Enum.with_index(assigns.compare || []),
        label: "#{assigns.title}, per bar in #{unit(assigns.unit)}",
        legend?: down_max > 0 and assigns.unit != :eur_kwh
      )

    ~H"""
    <.frame {frame_assigns(assigns)} compare?={@compare != nil}>
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
    </.frame>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :any, default: "mt-10"

  attr :points, :list,
    required: true,
    doc: "evenly spaced maps with :label, :up and :down in watts; nil :up means no data"

  @doc """
  Area chart of net power: use above the zero line, return below it. Points
  without data break the line.

  Hovering, tapping or dragging over the chart shows a point's value above it.
  """
  def power(assigns) do
    nets = for %{up: up, down: down} <- assigns.points, up != nil, do: up - down
    up_max = nets |> Enum.max(fn -> 0 end) |> max(0)
    down_max = nets |> Enum.min(fn -> 0 end) |> min(0) |> abs()

    assigns =
      assigns
      |> assign_axes(assigns.points, up_max, down_max, :w)
      |> assign(label: "#{assigns.title}, in watts", legend?: down_max > 0)

    assigns = assign(assigns, paths: power_paths(assigns))

    ~H"""
    <.frame {frame_assigns(assigns)}>
      <.net_paths id={@id} paths={@paths} zero={@zero} height={@height} />
      <rect
        :for={{point, i} <- Enum.with_index(@points)}
        data-bar={bar_title(point, :w)}
        data-dim="0"
        x={fmt(i * @width)}
        y="0"
        width={fmt(@width)}
        height={@height}
        class="fill-base-content/50 opacity-0"
      />
    </.frame>
    """
  end

  # One path per run of points with data. Each point sits mid-way its slot and
  # the run reaches the slot edges, so a lone point still shows.
  defp power_paths(%{points: points, width: width, zero: zero, scale: scale}) do
    y = fn point -> zero - (point.up - point.down) * scale end

    points
    |> Enum.with_index()
    |> Enum.chunk_by(fn {point, _i} -> is_nil(point.up) end)
    |> Enum.reject(fn [{point, _i} | _] -> is_nil(point.up) end)
    |> Enum.map(fn [{first, i} | _] = run ->
      {last, j} = List.last(run)
      middle = Enum.map(run, fn {point, i} -> {(i + 0.5) * width, y.(point)} end)
      area_paths([{i * width, y.(first)}] ++ middle ++ [{(j + 1) * width, y.(last)}], zero)
    end)
  end

  # A shared vertical scale, `up_max` above the zero line and `down_max` below.
  defp assign_axes(assigns, items, up_max, down_max, unit) do
    scale = if up_max + down_max > 0, do: @height / (up_max + down_max), else: 0
    zero = up_max * scale

    assign(assigns,
      scale: scale,
      zero: zero,
      height: @height,
      width: 100 / max(length(items), 1),
      grid: for(v <- gridlines(up_max), do: {value(v, unit), (zero - v * scale) / @height * 100}),
      ticks: ticks(items),
      summary: summary(up_max, down_max, unit)
    )
  end

  defp frame_assigns(assigns) do
    Map.take(assigns, [
      :id,
      :title,
      :class,
      :label,
      :summary,
      :grid,
      :ticks,
      :width,
      :height,
      :zero,
      :legend?
    ])
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :class, :any, required: true
  attr :label, :string, required: true
  attr :summary, :string, required: true
  attr :grid, :list, required: true, doc: "`{label, top_percent}` tuples"
  attr :ticks, :list, required: true, doc: "`{label, position}` tuples"
  attr :width, :float, required: true, doc: "width of one slot, in percent"
  attr :height, :integer, required: true
  attr :zero, :float, required: true
  attr :legend?, :boolean, required: true
  attr :compare?, :boolean, default: false
  slot :inner_block, required: true

  # The title, readout, axes and legend around a chart's marks. Elements with
  # `data-bar` hold the readout text per evenly spaced slot, in order. On
  # hover the others go to their `data-dim` opacity.
  defp frame(assigns) do
    ~H"""
    <section
      id={"#{@id}-chart"}
      aria-labelledby={"#{@id}-title"}
      class={["space-y-3", @class]}
      phx-hook=".ChartReadout"
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
          aria-label={@label}
        >
          <line
            :for={{_label, top} <- @grid}
            x1="0"
            x2="100"
            y1={top / 100 * @height}
            y2={top / 100 * @height}
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
          {render_slot(@inner_block)}
        </svg>
        <span
          :for={{label, top} <- @grid}
          class="pointer-events-none absolute left-0 -translate-y-full pb-0.5 text-[10px] tabular-nums text-base-content/50"
          style={"top: #{top}%"}
          aria-hidden="true"
        >
          {label}
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
      <p :if={@legend?} class="flex gap-4 text-xs text-base-content/60">
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-primary"></span>Used
        </span>
        <span class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-success"></span>Returned
        </span>
        <span :if={@compare?} class="flex items-center gap-1.5">
          <span class="size-2 rounded-sm bg-base-content/10"></span>Period before
        </span>
      </p>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChartReadout">
        export default {
          mounted() {
            this.active = null
            // By position, so a finger can drag along the chart.
            const pick = (e) => {
              const svg = e.target.closest("svg")
              if (!svg) return
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
            readout.textContent = active ? active.dataset.bar : readout.dataset.default
            readout.classList.toggle("text-base-content", !!active)
            bars.forEach((bar) => {
              bar.style.opacity = !active ? "" : bar === active ? "1" : (bar.dataset.dim ?? "0.4")
            })
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

  # At most six evenly spaced labels, on steps that suit 5 minutes, hours, days
  # and months.
  defp ticks(bars) do
    count = length(bars)
    step = Enum.find([1, 2, 3, 4, 6, 7, 12, 24, 48], 48, &(ceil(count / &1) <= 6))

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
        segment |> Enum.map(fn {t, w} -> {x.(t), y.(w)} end) |> area_paths(y.(0))
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
        <.net_paths id={@id} paths={@paths} zero={@zero} height={@height} />
      </svg>
      <figcaption class="flex justify-between text-xs text-base-content/60">
        <span>{div(@window, 60)} min ago</span>
        <span class="tabular-nums">peak {@top} W</span>
        <span>now</span>
      </figcaption>
    </figure>
    """
  end

  attr :id, :string, required: true
  attr :paths, :list, required: true
  attr :zero, :float, required: true
  attr :height, :integer, required: true

  # Lines with a filled area down to the zero line, in the use colour above it
  # and the return colour below it.
  defp net_paths(assigns) do
    ~H"""
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
    """
  end

  defp area_paths(coords, zero) do
    points = Enum.map(coords, fn {x, y} -> "#{fmt(x)},#{fmt(y)}" end)
    {first_x, _} = hd(coords)
    {last_x, _} = List.last(coords)

    %{
      line: "M" <> Enum.join(points, "L"),
      area:
        "M#{fmt(first_x)},#{fmt(zero)}L" <>
          Enum.join(points, "L") <> "L#{fmt(last_x)},#{fmt(zero)}Z"
    }
  end

  defp fmt(n), do: :erlang.float_to_binary(n / 1, decimals: 2)

  defp bar_title(%{up: nil} = point, _unit), do: "#{point.label}: no data"

  defp bar_title(bar, :eur_kwh),
    do: "#{bar.label}: #{value(bar.up - Map.get(bar, :down, 0), :eur_kwh)}"

  defp bar_title(%{down: down} = bar, unit) when down > 0,
    do: "#{bar.label}: #{value(bar.up, unit)} used, #{value(down, unit)} returned"

  defp bar_title(bar, unit), do: "#{bar.label}: #{value(bar.up, unit)}"

  defp value(v, :kwh), do: "#{kwh(v)} kWh"
  defp value(v, :m3), do: "#{m3(v)} m³"
  defp value(v, :eur_kwh), do: "€#{:erlang.float_to_binary(v / 1, decimals: 3)}/kWh"
  defp value(v, :w), do: "#{round(v)} W"

  defp unit(:kwh), do: "kWh"
  defp unit(:m3), do: "m³"
  defp unit(:eur_kwh), do: "€/kWh"
end
