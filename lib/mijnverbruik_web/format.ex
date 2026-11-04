defmodule MijnverbruikWeb.Format do
  @moduledoc """
  Number formatting for templates. Energy is stored as integer Wh and gas as
  integer litres.
  """

  def kwh(wh), do: :erlang.float_to_binary(wh / 1000, decimals: 2)
  def m3(l), do: :erlang.float_to_binary(l / 1000, decimals: 2)
end
