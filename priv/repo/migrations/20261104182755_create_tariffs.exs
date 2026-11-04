defmodule Mijnverbruik.Repo.Migrations.CreateTariffs do
  use Ecto.Migration

  def change do
    # A tariff applies from its date until the next tariff's date, so changing
    # contract never reprices the past.
    create table(:tariffs) do
      add :valid_from, :date, null: false
      add :electricity_low, :decimal, null: false
      add :electricity_normal, :decimal, null: false
      add :electricity_return, :decimal, null: false
      add :gas, :decimal, null: false
      add :fixed_per_month, :decimal, null: false
    end

    create unique_index(:tariffs, [:valid_from])
  end
end
