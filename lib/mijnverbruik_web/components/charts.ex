defmodule MijnverbruikWeb.Charts do
  @moduledoc """
  Server-rendered SVG charts.
  """
  use Phoenix.Component

  import MijnverbruikWeb.Format

  @height 40

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :unit, :atom, values: [:kwh, :m3], required: true
  attr :bars, :list, required: true, doc: "maps with :label, :up and optional :down"

  @doc """
  Bar chart with usage going up from the zero line and, when any bar has a
  `:down` value, return going down from it. Values are Wh for `:kwh` and
  litres for `:m3`.
  """
  def bars(assigns) do
    up_max = assigns.bars |> Enum.map(& &1.up) |> Enum.max(fn -> 0 end)
    down_max = assigns.bars |> Enum.map(&Map.get(&1, :down, 0)) |> Enum.max(fn -> 0 end)
    scale = @height / max(up_max + down_max, 1)

    assigns =
      assign(assigns,
        up_max: up_max,
        down_max: down_max,
        scale: scale,
        zero: up_max * scale,
        width: 100 / max(length(assigns.bars), 1),
        height: @height
      )

    ~H"""
    <section aria-labelledby={"#{@id}-title"} class="mt-10 space-y-3">
      <div class="flex items-baseline justify-between">
        <h2 id={"#{@id}-title"} class="text-sm font-medium text-base-content/60">{@title}</h2>
        <p class="text-xs tabular-nums text-base-content/60">
          max {value(@up_max, @unit)}
          <span :if={@down_max > 0}>· returned max {value(@down_max, @unit)}</span>
        </p>
      </div>
      <svg
        id={@id}
        viewBox={"0 0 100 #{@height}"}
        preserveAspectRatio="none"
        class="h-40 w-full"
        role="img"
        aria-label={"#{@title}, per bar in #{unit(@unit)}"}
      >
        <line
          :if={@down_max > 0}
          x1="0"
          x2="100"
          y1={@zero}
          y2={@zero}
          class="stroke-base-content/20"
          stroke-width="0.2"
          vector-effect="non-scaling-stroke"
        />
        <g :for={{bar, i} <- Enum.with_index(@bars)}>
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
      </svg>
      <div class="flex justify-between text-xs text-base-content/60">
        <span>{List.first(@bars).label}</span>
        <span>{List.last(@bars).label}</span>
      </div>
    </section>
    """
  end

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
        <g :for={path <- @paths}>
          <path d={path.area} class="fill-primary/15" />
          <path
            d={path.line}
            class="fill-none stroke-primary"
            stroke-width="1.5"
            stroke-linejoin="round"
            vector-effect="non-scaling-stroke"
          />
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

  defp bar_title(%{down: down} = bar, unit) when down > 0,
    do: "#{bar.label}: #{value(bar.up, unit)} used, #{value(down, unit)} returned"

  defp bar_title(bar, unit), do: "#{bar.label}: #{value(bar.up, unit)}"

  defp value(v, :kwh), do: "#{kwh(v)} kWh"
  defp value(v, :m3), do: "#{m3(v)} m³"

  defp unit(:kwh), do: "kWh"
  defp unit(:m3), do: "m³"
end
