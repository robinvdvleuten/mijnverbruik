defmodule Mijnverbruik.Tariffs do
  @moduledoc """
  Dated energy tariffs and the costs they give to usage.
  """
  import Ecto.Query

  alias Mijnverbruik.{Prices, Repo}
  alias Mijnverbruik.Tariffs.Tariff

  @doc "All tariffs, newest first."
  def list_tariffs, do: Repo.all(from t in Tariff, order_by: [desc: t.valid_from])

  def get_tariff!(id), do: Repo.get!(Tariff, id)

  def change_tariff(%Tariff{} = tariff, attrs \\ %{}), do: Tariff.changeset(tariff, attrs)

  def create_tariff(attrs), do: %Tariff{} |> Tariff.changeset(attrs) |> Repo.insert()

  def update_tariff(%Tariff{} = tariff, attrs),
    do: tariff |> Tariff.changeset(attrs) |> Repo.update()

  def delete_tariff(%Tariff{} = tariff), do: Repo.delete(tariff)

  @doc """
  The tariff valid on `date` from `tariffs` (newest first), or nil.
  """
  def valid_on(tariffs, %Date{} = date),
    do: Enum.find(tariffs, &(Date.compare(&1.valid_from, date) != :gt))

  @doc """
  Energy cost in euros of a usage map with `:delivered_t1_wh` (low tariff),
  `:delivered_t2_wh` (normal tariff), `:returned_wh` and `:gas_l`. Return
  lowers the cost.

  Dynamic contracts need the hour's market prices excluding VAT in `market`,
  as `%{electricity: euros_per_kwh, gas: euros_per_m3}`; when a needed price
  is missing the cost is nil.
  """
  def energy_cost(%Tariff{} = t, usage, market \\ %{}) do
    with electricity when is_number(electricity) <-
           electricity_cost(t, usage, market[:electricity]),
         gas when is_number(gas) <- gas_cost(t, usage, market[:gas]) do
      electricity + gas
    end
  end

  defp electricity_cost(%Tariff{contract: :dynamic}, _usage, nil), do: nil

  defp electricity_cost(%Tariff{contract: :dynamic} = t, usage, market) do
    usage.delivered_wh / 1000 * kwh_price(t, market) -
      usage.returned_wh / 1000 * (with_vat(market) + price(t.electricity_return))
  end

  defp electricity_cost(%Tariff{} = t, usage, _market) do
    usage.delivered_t1_wh / 1000 * price(t.electricity_low) +
      usage.delivered_t2_wh / 1000 * price(t.electricity_normal) -
      usage.returned_wh / 1000 * price(t.electricity_return)
  end

  # Without gas use, a missing gas price does not matter.
  defp gas_cost(_tariff, %{gas_l: 0}, _market), do: 0
  defp gas_cost(%Tariff{gas_contract: :dynamic}, _usage, nil), do: nil
  defp gas_cost(%Tariff{} = t, usage, market), do: usage.gas_l / 1000 * m3_price(t, market)

  @doc """
  What a m³ of gas costs, including taxes. For a dynamic gas contract this
  needs the gas day's `market` price (excluding VAT).
  """
  def m3_price(%Tariff{gas_contract: :dynamic} = t, market), do: with_vat(market) + price(t.gas)
  def m3_price(%Tariff{} = t, _market), do: price(t.gas)

  defp with_vat(market), do: market * (1 + Prices.vat())

  @doc """
  What a kWh taken from the grid costs, including taxes. For a dynamic
  contract this needs the `market` price (excluding VAT).
  """
  def kwh_price(%Tariff{contract: :dynamic} = t, market),
    do: with_vat(market) + price(t.electricity_surcharge)

  def kwh_price(%Tariff{} = t, _market),
    do: (price(t.electricity_low) + price(t.electricity_normal)) / 2

  @doc "Fixed costs in euros for one day."
  def fixed_per_day(%Tariff{} = t), do: price(t.fixed_per_month) * 12 / 365

  defp price(%Decimal{} = d), do: Decimal.to_float(d)
end
