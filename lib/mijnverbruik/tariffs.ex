defmodule Mijnverbruik.Tariffs do
  @moduledoc """
  Dated energy tariffs and the costs they give to usage.
  """
  import Ecto.Query

  alias Mijnverbruik.Repo
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
  """
  def energy_cost(%Tariff{} = t, usage) do
    usage.delivered_t1_wh / 1000 * price(t.electricity_low) +
      usage.delivered_t2_wh / 1000 * price(t.electricity_normal) -
      usage.returned_wh / 1000 * price(t.electricity_return) +
      usage.gas_l / 1000 * price(t.gas)
  end

  @doc "Fixed costs in euros for one day."
  def fixed_per_day(%Tariff{} = t), do: price(t.fixed_per_month) * 12 / 365

  defp price(%Decimal{} = d), do: Decimal.to_float(d)
end
