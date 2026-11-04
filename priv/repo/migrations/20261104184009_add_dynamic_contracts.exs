defmodule Mijnverbruik.Repo.Migrations.AddDynamicContracts do
  use Ecto.Migration

  # SQLite cannot drop NOT NULL from a column, so the table is rebuilt: a
  # dynamic contract has no fixed low and normal electricity prices.
  def up do
    create table(:tariffs_new) do
      add :valid_from, :date, null: false
      add :contract, :string, null: false, default: "fixed"
      add :electricity_low, :decimal
      add :electricity_normal, :decimal
      add :electricity_surcharge, :decimal
      add :electricity_return, :decimal, null: false
      add :gas, :decimal, null: false
      add :fixed_per_month, :decimal, null: false
    end

    execute """
    INSERT INTO tariffs_new (id, valid_from, electricity_low, electricity_normal,
                             electricity_return, gas, fixed_per_month)
    SELECT id, valid_from, electricity_low, electricity_normal,
           electricity_return, gas, fixed_per_month
    FROM tariffs
    """

    drop table(:tariffs)
    rename table(:tariffs_new), to: table(:tariffs)
    create unique_index(:tariffs, [:valid_from])
  end

  def down do
    create table(:tariffs_old) do
      add :valid_from, :date, null: false
      add :electricity_low, :decimal, null: false
      add :electricity_normal, :decimal, null: false
      add :electricity_return, :decimal, null: false
      add :gas, :decimal, null: false
      add :fixed_per_month, :decimal, null: false
    end

    execute """
    INSERT INTO tariffs_old (id, valid_from, electricity_low, electricity_normal,
                             electricity_return, gas, fixed_per_month)
    SELECT id, valid_from, electricity_low, electricity_normal,
           electricity_return, gas, fixed_per_month
    FROM tariffs WHERE contract = 'fixed'
    """

    drop table(:tariffs)
    rename table(:tariffs_old), to: table(:tariffs)
    create unique_index(:tariffs, [:valid_from])
  end
end
