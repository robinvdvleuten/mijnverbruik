defmodule Mijnverbruik.Settings.Setting do
  @moduledoc """
  Household-wide settings, stored as the single row with id 1.

  `main_fuse_a` is the rating of the main fuse per phase in amperes.
  `latitude` and `longitude` place the home, for sunrise and sunset.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @fuses [25, 35, 40, 50, 63, 80]

  def fuses, do: @fuses

  schema "settings" do
    field :main_fuse_a, :integer
    field :latitude, :float
    field :longitude, :float
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:main_fuse_a, :latitude, :longitude])
    |> validate_inclusion(:main_fuse_a, @fuses)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_location()
  end

  # Half a location cannot place the sun.
  defp validate_location(changeset) do
    case {get_field(changeset, :latitude), get_field(changeset, :longitude)} do
      {nil, lon} when lon != nil -> add_error(changeset, :latitude, "can't be blank")
      {lat, nil} when lat != nil -> add_error(changeset, :longitude, "can't be blank")
      _ -> changeset
    end
  end
end
