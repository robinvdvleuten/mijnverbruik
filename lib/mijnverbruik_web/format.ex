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

  @doc "Euros, by default with two decimals, e.g. `€ 1,23` or `−€ 0,40`."
  def euro(amount, places \\ 2) do
    rounded = Float.round(amount / 1, places)
    if(rounded < 0, do: "−", else: "") <> "€ " <> decimal(abs(rounded), places)
  end

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

  @doc "A date as `9 nov 2026`."
  def short_date(%Date{} = date), do: "#{date.day} #{short_month(date)} #{date.year}"

  @doc "The weekday's first two letters and the day, e.g. `ma 9`."
  def weekday_day(%Date{} = date), do: "#{date |> weekday() |> String.slice(0, 2)} #{date.day}"

  @doc "A duration in seconds as Dutch words, e.g. `6 minuten`."
  def ago(seconds) when seconds < 60, do: "#{max(seconds, 0)} seconden"
  def ago(seconds) when seconds < 120, do: "1 minuut"
  def ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} minuten"
  def ago(seconds) when seconds < 7200, do: "1 uur"
  def ago(seconds), do: "#{div(seconds, 3600)} uur"

  @doc "The household's timezone."
  def timezone, do: Application.fetch_env!(:mijnverbruik, :timezone)

  @doc "Unix seconds as local time in `format`, e.g. `local_time(t, \"%H:%M\")`."
  def local_time(unix, format) do
    unix |> DateTime.from_unix!() |> DateTime.shift_zone!(timezone()) |> Calendar.strftime(format)
  end
end
