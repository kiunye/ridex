defmodule RidexWeb.Router do
  use RidexWeb, :router

  import RidexWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RidexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :fetch_current_user
  end

  scope "/", RidexWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", RidexWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", RidexWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{RidexWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", RidexWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{RidexWeb.UserAuth, :ensure_authenticated}] do
      live "/driver/dashboard", DriverDashboardLive, :index
      live "/rider/dashboard", RiderDashboardLive, :index
    end
  end

  scope "/", RidexWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete
  end

  # API routes
  scope "/api", RidexWeb do
    pipe_through [:api, :require_authenticated_user]

    post "/trips/:id/accept", TripController, :accept
    post "/trips/:id/decline", TripController, :decline
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ridex, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RidexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
