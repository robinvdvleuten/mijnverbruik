defmodule MijnverbruikWeb.Format do
  @moduledoc """
  Dutch number and date formatting for templates: a decimal comma, a dot
  between thousands and `€ 1,23`. Energy is stored as integer Wh and gas as
  integer litres.
  """

  @days ~w(maandag dinsdag woensdag donderdag vrijdag zaterdag zondag)
  @months ~w(januari februari maart april mei juni juli augustus september oktober november december)

  @doc "Wh as kWh with two decimals, e.g. `2,14`."
  def kwh(wh), do: decimal(wh / 1000, 2)

  @doc "Litres as m³ with two decimals, e.g. `0,58`."
  def m3(l), do: decimal(l / 1000, 2)

  @doc "Whole watts with a thousands separator, e.g. `1.222`."
  def watts(w), do: w |> round() |> integer()

  @doc "Euros with two decimals, e.g. `€ 1,23` or `−€ 0,40`."
  def euro(amount) when amount < -0.005, do: "−€ " <> decimal(-amount, 2)
  def euro(amount), do: "€ " <> decimal(abs(amount), 2)

  @doc "A number with a decimal comma and `places` decimals."
  def decimal(n, places) do
    [whole | frac] =
      n |> Kernel./(1) |> :erlang.float_to_binary(decimals: places) |> String.split(".")

    {sign, whole} =
      if String.starts_with?(whole, "-"),
        do: {"−", String.trim_leading(whole, "-")},
        else: {"", whole}

    sign <> (whole |> String.to_integer() |> integer()) <> Enum.map_join(frac, &("," <> &1))
  end

  @doc "A price with up to five decimals, trailing zeros trimmed to two, e.g. `0,24871`."
  def price(%Decimal{} = d) do
    d |> Decimal.round(5) |> Decimal.normalize() |> Decimal.to_string(:normal) |> pad_cents()
  end

  defp pad_cents(s) do
    case String.split(s, ".") do
      [whole] -> whole <> ",00"
      [whole, frac] -> whole <> "," <> String.pad_trailing(frac, 2, "0")
    end
  end

  defp integer(n) when n < 0, do: "−" <> integer(-n)

  defp integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.chunk_every(3)
    |> Enum.join(".")
    |> String.reverse()
  end

  @doc "A date as `maandag 9 november`."
  def day_month(%Date{} = date),
    do: "#{weekday(date)} #{date.day} #{month(date)}"

  @doc "The Dutch weekday name of a date."
  def weekday(%Date{} = date), do: Enum.at(@days, Date.day_of_week(date) - 1)

  @doc "The Dutch month name of a date."
  def month(%Date{} = date), do: Enum.at(@months, date.month - 1)

  @doc "The first three letters of the month, e.g. `nov`."
  def short_month(%Date{} = date), do: date |> month() |> String.slice(0, 3)
end
