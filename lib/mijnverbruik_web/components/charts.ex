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

  defp bar_title(%{down: down} = bar, unit) when down > 0,
    do: "#{bar.label}: #{value(bar.up, unit)} used, #{value(down, unit)} returned"

  defp bar_title(bar, unit), do: "#{bar.label}: #{value(bar.up, unit)}"

  defp value(v, :kwh), do: "#{kwh(v)} kWh"
  defp value(v, :m3), do: "#{m3(v)} m³"

  defp unit(:kwh), do: "kWh"
  defp unit(:m3), do: "m³"
end
