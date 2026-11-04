defmodule Mijnverbruik.Repo.Migrations.CreateReadings do
  use Ecto.Migration

  def change do
    # One row per minute holding the meter's cumulative registers. Energy for any
    # period is the difference between two rows, so gaps never lose kWh.
    create table(:readings, primary_key: false) do
      add :minute, :integer, primary_key: true
      add :equipment_id, :string, null: false
      add :delivered_t1_wh, :integer, null: false
      add :delivered_t2_wh, :integer, null: false
      add :returned_t1_wh, :integer, null: false
      add :returned_t2_wh, :integer, null: false
      add :gas_l, :integer
    end
  end
end
