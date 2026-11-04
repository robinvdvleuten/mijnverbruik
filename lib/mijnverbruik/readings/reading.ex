defmodule Mijnverbruik.Readings.Reading do
  @moduledoc """
  Snapshot of the meter's cumulative registers at the start of a minute.

  `minute` is unix seconds floored to the minute (UTC). Energy is stored as
  integer Wh and gas as integer litres.
  """
  use Ecto.Schema

  @primary_key {:minute, :integer, autogenerate: false}
  schema "readings" do
    field :equipment_id, :string
    field :delivered_t1_wh, :integer
    field :delivered_t2_wh, :integer
    field :returned_t1_wh, :integer
    field :returned_t2_wh, :integer
    field :gas_l, :integer
  end
end
