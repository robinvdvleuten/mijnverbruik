defmodule Mijnverbruik.Repo do
  use Ecto.Repo,
    otp_app: :mijnverbruik,
    adapter: Ecto.Adapters.SQLite3
end
