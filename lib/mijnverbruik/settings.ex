defmodule Mijnverbruik.Settings do
  @moduledoc """
  Household-wide settings. Tariffs live in `Mijnverbruik.Tariffs`.
  """
  alias Mijnverbruik.Repo
  alias Mijnverbruik.Settings.Setting

  @doc "The settings, with defaults when none are saved yet."
  def get, do: Repo.get(Setting, 1) || %Setting{id: 1}

  # De Bilt, the middle of the Netherlands, until a location is set.
  @default_location %{latitude: 52.1, longitude: 5.18}

  @doc "The home's latitude and longitude, or the default when not set."
  def location do
    case get() do
      %Setting{latitude: lat, longitude: lon} when is_float(lat) and is_float(lon) ->
        %{latitude: lat, longitude: lon}

      _ ->
        @default_location
    end
  end

  def change(%Setting{} = setting, attrs \\ %{}), do: Setting.changeset(setting, attrs)

  def update(attrs) do
    get()
    |> Setting.changeset(attrs)
    |> Repo.insert_or_update()
  end
end
