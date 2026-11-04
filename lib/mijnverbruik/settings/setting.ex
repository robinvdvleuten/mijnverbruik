defmodule Mijnverbruik.Settings.Setting do
  @moduledoc """
  Household-wide settings, stored as the single row with id 1.

  `main_fuse_a` is the rating of the main fuse per phase in amperes.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @fuses [25, 35, 40, 50, 63, 80]

  def fuses, do: @fuses

  schema "settings" do
    field :main_fuse_a, :integer
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:main_fuse_a])
    |> validate_inclusion(:main_fuse_a, @fuses)
  end
end
