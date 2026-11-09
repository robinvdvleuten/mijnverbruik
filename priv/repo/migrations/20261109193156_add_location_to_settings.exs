defmodule Mijnverbruik.Repo.Migrations.AddLocationToSettings do
  use Ecto.Migration

  def change do
    # Where the home is, for sunrise and sunset. Nil means the default.
    alter table(:settings) do
      add :latitude, :float
      add :longitude, :float
    end
  end
end
