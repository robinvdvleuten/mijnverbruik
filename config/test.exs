import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mijnverbruik, Mijnverbruik.Repo,
  database: Path.expand("../mijnverbruik_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mijnverbruik, MijnverbruikWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "OD3X86Ll2XRT2Py/1QEL8e0IjoeEbxHrl43VUpTXdt7+yRK5kj1DH6LaomuEovfX",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Never fetch market prices over the network in tests.
config :mijnverbruik, fetch_prices: false
config :mijnverbruik, prices_req_options: [plug: {Req.Test, Mijnverbruik.Prices}, retry: false]
