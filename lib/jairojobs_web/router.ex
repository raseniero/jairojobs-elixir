defmodule JairojobsWeb.Router do
  use JairojobsWeb, :router

  import JairojobsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JairojobsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", JairojobsWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", JairojobsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jairojobs, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JairojobsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", JairojobsWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{JairojobsWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Admin routes (spec 001, plan decision 7) — first used by spec 002; 004 and 008 add more.
  # Every admin-only LiveView goes inside this one `live_session :require_admin`.
  scope "/admin", JairojobsWeb.Admin do
    pipe_through [:browser, :require_admin]

    live_session :require_admin,
      on_mount: [{JairojobsWeb.UserAuth, :require_admin}] do
      live "/", HomeLive
      live "/regions", RegionLive.Index, :index
      live "/regions/new", RegionLive.Form, :new
      live "/regions/:id/edit", RegionLive.Form, :edit
    end
  end

  ## Posting routes (spec 003) — for Employers and Admins (REQ-003-1).
  # Candidates must be refused, so these cannot sit in `:require_authenticated_user`;
  # Employers must get in, so they cannot sit in `:require_admin`.
  scope "/my", JairojobsWeb.Employer do
    pipe_through [:browser, :require_poster]

    live_session :require_poster,
      on_mount: [{JairojobsWeb.UserAuth, :require_poster}] do
      live "/business", BusinessLive, :edit
      live "/listings", ListingLive.Index, :index
      live "/listings/new", ListingLive.Form, :new
      live "/listings/:id/edit", ListingLive.Form, :edit
    end
  end

  scope "/", JairojobsWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{JairojobsWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
