defmodule Mijnverbruik.Repo.Migrations.CreateMarketPrices do
  use Ecto.Migration

  def change do
    # Day-ahead electricity prices per UTC hour, in euros per kWh excluding VAT.
    create table(:market_prices, primary_key: false) do
      add :hour, :integer, primary_key: true
      add :price, :float, null: false
    end
  end
end
