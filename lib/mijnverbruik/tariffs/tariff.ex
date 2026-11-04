defmodule Mijnverbruik.Tariffs.Tariff do
  @moduledoc """
  Energy prices valid from `valid_from` (a local date) until the next tariff.

  Prices are euros including taxes: per kWh for electricity, per m³ for gas.
  `fixed_per_month` covers standing charges and grid fees minus the energy
  tax credit, so it can be negative.

  A `:fixed` contract sets `electricity_low` and `electricity_normal`. A
  `:dynamic` contract pays the hourly market price plus VAT plus
  `electricity_surcharge` (energy tax and supplier markup), and returned
  electricity earns the market price plus VAT plus `electricity_return`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "tariffs" do
    field :valid_from, :date
    field :contract, Ecto.Enum, values: [:fixed, :dynamic], default: :fixed
    field :electricity_low, :decimal
    field :electricity_normal, :decimal
    field :electricity_surcharge, :decimal
    field :electricity_return, :decimal
    field :gas, :decimal
    field :fixed_per_month, :decimal
  end

  @fields [
    :valid_from,
    :contract,
    :electricity_low,
    :electricity_normal,
    :electricity_surcharge,
    :electricity_return,
    :gas,
    :fixed_per_month
  ]

  def changeset(tariff, attrs) do
    tariff
    |> cast(attrs, @fields)
    |> validate_required([:valid_from, :contract, :electricity_return, :gas, :fixed_per_month])
    |> validate_number(:gas, greater_than_or_equal_to: 0)
    |> validate_contract()
    |> unique_constraint(:valid_from, message: "another tariff starts on this date")
  end

  defp validate_contract(changeset) do
    case get_field(changeset, :contract) do
      :dynamic ->
        changeset
        |> validate_required([:electricity_surcharge])
        |> put_change(:electricity_low, nil)
        |> put_change(:electricity_normal, nil)

      _fixed ->
        prices = [:electricity_low, :electricity_normal, :electricity_return]

        changeset
        |> validate_required(prices)
        |> then(fn cs ->
          Enum.reduce(prices, cs, &validate_number(&2, &1, greater_than_or_equal_to: 0))
        end)
        |> put_change(:electricity_surcharge, nil)
    end
  end
end
