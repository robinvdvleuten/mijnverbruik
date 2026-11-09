defmodule Mijnverbruik.Meter do
  @moduledoc """
  Live meter data: telegrams broadcast by `Mijnverbruik.Meter.Reader`, and
  `:meter_offline` when its connection fails.
  """

  @topic "telegrams"

  def subscribe, do: Phoenix.PubSub.subscribe(Mijnverbruik.PubSub, @topic)

  def broadcast(%DSMR.Telegram{} = telegram),
    do: Phoenix.PubSub.broadcast(Mijnverbruik.PubSub, @topic, {:telegram, telegram})

  @doc """
  Tells subscribers the connection to the meter was lost. The next telegram
  means it is back.
  """
  def broadcast_offline,
    do: Phoenix.PubSub.broadcast(Mijnverbruik.PubSub, @topic, :meter_offline)

  @doc """
  Instantaneous values from a telegram: net power in W (negative when
  returning) and per-phase W and A.
  """
  def live(%DSMR.Telegram{} = t) do
    %{
      power_w: watts(t.electricity_currently_delivered) - watts(t.electricity_currently_returned),
      phases:
        for {d, r, a} <- [
              {t.currently_delivered_l1, t.currently_returned_l1, t.phase_power_current_l1},
              {t.currently_delivered_l2, t.currently_returned_l2, t.phase_power_current_l2},
              {t.currently_delivered_l3, t.currently_returned_l3, t.phase_power_current_l3}
            ],
            d != nil do
          %{power_w: watts(d) - watts(r), current_a: value(a)}
        end
    }
  end

  @doc """
  What a telegram tells about the meter: its `:make` (nil when unknown), the
  DSMR `:version` as an integer such as 50 (nil when missing), the number of
  `:phases`, and how often a `:gas` meter reports: `:five_minutes` (DSMR 5),
  `:hourly` (older) or nil without one.
  """
  def info(%DSMR.Telegram{} = t) do
    version =
      case Integer.parse(t.version || "") do
        {n, _} -> n
        :error -> nil
      end

    gas? = Enum.any?(t.mbus_devices, &(&1.device_type == "003"))

    %{
      make: make(t.header),
      version: version,
      phases: length(live(t).phases),
      gas:
        cond do
          not gas? -> nil
          version && version >= 50 -> :five_minutes
          true -> :hourly
        end
    }
  end

  # The header starts with the maker's three-letter flag code.
  @makes %{
    "ISK" => "Iskra",
    "KFM" => "Kaifa",
    "KMP" => "Kamstrup",
    "XMX" => "Xemex",
    "LGB" => "Landis+Gyr",
    "LGF" => "Landis+Gyr",
    "ENE" => "Sagemcom",
    "SAG" => "Sagemcom"
  }

  defp make(header) when is_binary(header) do
    header = String.trim_leading(header, "/")
    Map.get(@makes, header |> String.slice(0, 3) |> String.upcase(), header)
  end

  defp make(_header), do: nil

  defp watts(m), do: round(value(m) * 1000)

  defp value(%DSMR.Measurement{value: v}) when is_number(v), do: v
  defp value(_), do: 0
end
