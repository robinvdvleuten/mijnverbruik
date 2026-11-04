defmodule Mijnverbruik.Tariffs.Tariff do
  @moduledoc """
  Energy prices valid from `valid_from` (a local date) until the next tariff.

  Prices are euros including taxes: per kWh for electricity, per m³ for gas.
  `fixed_per_month` covers standing charges and grid fees minus the energy
  tax credit, so it can be negative.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @prices [:electricity_low, :electricity_normal, :electricity_return, :gas]

  schema "tariffs" do
    field :valid_from, :date
    field :electricity_low, :decimal
    field :electricity_normal, :decimal
    field :electricity_return, :decimal
    field :gas, :decimal
    field :fixed_per_month, :decimal
  end

  def changeset(tariff, attrs) do
    tariff
    |> cast(attrs, [:valid_from, :fixed_per_month | @prices])
    |> validate_required([:valid_from, :fixed_per_month | @prices])
    |> then(fn cs ->
      Enum.reduce(@prices, cs, &validate_number(&2, &1, greater_than_or_equal_to: 0))
    end)
    |> unique_constraint(:valid_from, message: "another tariff starts on this date")
  end
end
