defmodule Mijnverbruik.Repo.Migrations.AddDynamicGas do
  use Ecto.Migration

  def up do
    alter table(:tariffs) do
      add :gas_contract, :string, null: false, default: "fixed"
    end

    # Market prices gain a commodity, which joins the primary key. SQLite
    # cannot change a primary key, so the table is rebuilt.
    create table(:market_prices_new, primary_key: false) do
      add :hour, :integer, primary_key: true
      add :commodity, :string, primary_key: true
      add :price, :float, null: false
    end

    execute """
    INSERT INTO market_prices_new (hour, commodity, price)
    SELECT hour, 'electricity', price FROM market_prices
    """

    drop table(:market_prices)
    rename table(:market_prices_new), to: table(:market_prices)
  end

  def down do
    create table(:market_prices_old, primary_key: false) do
      add :hour, :integer, primary_key: true
      add :price, :float, null: false
    end

    execute """
    INSERT INTO market_prices_old (hour, price)
    SELECT hour, price FROM market_prices WHERE commodity = 'electricity'
    """

    drop table(:market_prices)
    rename table(:market_prices_old), to: table(:market_prices)

    alter table(:tariffs) do
      remove :gas_contract
    end
  end
end
