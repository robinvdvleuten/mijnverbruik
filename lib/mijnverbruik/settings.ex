defmodule Mijnverbruik.Settings do
  @moduledoc """
  Household-wide settings. Tariffs live in `Mijnverbruik.Tariffs`.
  """
  alias Mijnverbruik.Repo
  alias Mijnverbruik.Settings.Setting

  @doc "The settings, with defaults when none are saved yet."
  def get, do: Repo.get(Setting, 1) || %Setting{id: 1}

  def change(%Setting{} = setting, attrs \\ %{}), do: Setting.changeset(setting, attrs)

  def update(attrs) do
    get()
    |> Setting.changeset(attrs)
    |> Repo.insert_or_update()
  end
end
