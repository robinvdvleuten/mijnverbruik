defmodule Mijnverbruik.Prices.MarketPrice do
  @moduledoc """
  Day-ahead electricity price for one UTC hour (`hour` in unix seconds), in
  euros per kWh excluding VAT.
  """
  use Ecto.Schema

  @primary_key {:hour, :integer, autogenerate: false}
  schema "market_prices" do
    field :price, :float
  end
end
