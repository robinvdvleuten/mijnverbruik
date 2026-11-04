defmodule Mijnverbruik.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    # A single row (id 1) with household-wide settings.
    create table(:settings) do
      add :main_fuse_a, :integer
    end
  end
end
