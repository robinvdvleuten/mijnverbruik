defmodule Mijnverbruik.Prices.MarketPrice do
  @moduledoc """
  Market price of a commodity for one UTC hour (`hour` in unix seconds),
  excluding VAT: euros per kWh for `:electricity`, per m³ for `:gas`. Gas
  is priced per gas day, so its 24 hours share one price.
  """
  use Ecto.Schema

  @primary_key false
  schema "market_prices" do
    field :hour, :integer, primary_key: true
    field :commodity, Ecto.Enum, values: [:electricity, :gas], primary_key: true
    field :price, :float
  end
end
