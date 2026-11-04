defmodule MijnverbruikWeb.Format do
  @moduledoc """
  Number formatting for templates. Energy is stored as integer Wh and gas as
  integer litres.
  """

  def kwh(wh), do: :erlang.float_to_binary(wh / 1000, decimals: 2)
  def m3(l), do: :erlang.float_to_binary(l / 1000, decimals: 2)

  @doc "Euros with two decimals, e.g. `€1.23` or `−€0.40`."
  def euro(amount) when amount < -0.005,
    do: "−€" <> :erlang.float_to_binary(-amount / 1, decimals: 2)

  def euro(amount), do: "€" <> :erlang.float_to_binary(abs(amount) / 1, decimals: 2)

  @doc "A price with up to five decimals, trailing zeros trimmed to two."
  def price(%Decimal{} = d) do
    d |> Decimal.round(5) |> Decimal.normalize() |> Decimal.to_string(:normal) |> pad_cents()
  end

  defp pad_cents(s) do
    case String.split(s, ".") do
      [whole] -> whole <> ".00"
      [whole, frac] -> whole <> "." <> String.pad_trailing(frac, 2, "0")
    end
  end
end
