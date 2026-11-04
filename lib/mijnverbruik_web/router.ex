defmodule MijnverbruikWeb.Router do
  use MijnverbruikWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MijnverbruikWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MijnverbruikWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/history", HistoryLive
    live "/settings", SettingsLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", MijnverbruikWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:mijnverbruik, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MijnverbruikWeb.Telemetry
    end
  end
end
