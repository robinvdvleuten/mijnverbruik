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

  A dynamic contract needs the hour's `market` price (euros per kWh excluding
  VAT); without it the cost is nil.
  """
  def energy_cost(tariff, usage, market \\ nil)

  def energy_cost(%Tariff{contract: :dynamic}, _usage, nil), do: nil

  def energy_cost(%Tariff{contract: :dynamic} = t, usage, market) do
    usage.delivered_wh / 1000 * kwh_price(t, market) -
      usage.returned_wh / 1000 * return_price(t, market) +
      usage.gas_l / 1000 * price(t.gas)
  end

  def energy_cost(%Tariff{} = t, usage, _market) do
    usage.delivered_t1_wh / 1000 * price(t.electricity_low) +
      usage.delivered_t2_wh / 1000 * price(t.electricity_normal) -
      usage.returned_wh / 1000 * price(t.electricity_return) +
      usage.gas_l / 1000 * price(t.gas)
  end

  @doc """
  What a kWh taken from the grid costs, including taxes. For a dynamic
  contract this needs the `market` price (excluding VAT).
  """
  def kwh_price(%Tariff{contract: :dynamic} = t, market),
    do: market * (1 + Prices.vat()) + price(t.electricity_surcharge)

  def kwh_price(%Tariff{} = t, _market),
    do: (price(t.electricity_low) + price(t.electricity_normal)) / 2

  defp return_price(t, market), do: market * (1 + Prices.vat()) + price(t.electricity_return)

  @doc "Fixed costs in euros for one day."
  def fixed_per_day(%Tariff{} = t), do: price(t.fixed_per_month) * 12 / 365

  defp price(%Decimal{} = d), do: Decimal.to_float(d)
end
