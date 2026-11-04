defmodule Mijnverbruik.Meter do
  @moduledoc """
  Live meter data: telegrams broadcast by `Mijnverbruik.Meter.Reader`.
  """

  @topic "telegrams"

  def subscribe, do: Phoenix.PubSub.subscribe(Mijnverbruik.PubSub, @topic)

  def broadcast(%DSMR.Telegram{} = telegram),
    do: Phoenix.PubSub.broadcast(Mijnverbruik.PubSub, @topic, {:telegram, telegram})

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

  defp watts(m), do: round(value(m) * 1000)

  defp value(%DSMR.Measurement{value: v}) when is_number(v), do: v
  defp value(_), do: 0
end
