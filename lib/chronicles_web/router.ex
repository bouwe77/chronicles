defmodule ChroniclesWeb.Router do
  use ChroniclesWeb, :router

  import ChroniclesWeb.UserAuth
  import ChroniclesWeb.APIAuth, only: [require_api_user: 2]
  import ChroniclesWeb.Locale, only: [put_locale: 2]
  import ChroniclesWeb.RateLimit, only: [rate_limit: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChroniclesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug :put_locale
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :rate_limit
  end

  scope "/", ChroniclesWeb do
    pipe_through :browser

    get "/", PageController, :home
    put "/locale", LocaleController, :update
  end

  # The JSON API, for tools and scripts. See ChroniclesWeb.APIAuth.
  scope "/api", ChroniclesWeb.API do
    pipe_through :api

    post "/session", SessionController, :create
  end

  scope "/api", ChroniclesWeb.API do
    pipe_through [:api, :require_api_user]

    resources "/stories", StoryController, only: [:index, :show, :update, :delete], param: "slug"
    resources "/series", SeriesController, only: [:index, :show, :update, :delete], param: "slug"
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:chronicles, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ChroniclesWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", ChroniclesWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ChroniclesWeb.UserAuth, :require_authenticated}] do
      live "/account", UserLive.Account, :edit
      live "/account/confirm-email/:token", UserLive.Account, :confirm_email

      live "/stories", StoriesLive
      # Before /stories/:slug, which would take "upload" or "new" as a slug.
      live "/stories/upload", StoryUploadLive
      live "/stories/new", NewStoryLive
      live "/stories/:slug", StoryLive
      live "/stories/:slug/edit", EditStoryLive
      live "/games/:id", GameLive
    end

    post "/users/update-password", UserSessionController, :update_password
    get "/story-kit/:file", StoryKitController, :show

    live_session :require_admin,
      on_mount: [
        {ChroniclesWeb.UserAuth, :require_authenticated},
        {ChroniclesWeb.UserAuth, :require_admin}
      ] do
      live "/admin/users", Admin.UsersLive
    end
  end

  scope "/", ChroniclesWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ChroniclesWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      # Language and theme, which visitors can change too.
      live "/settings", SettingsLive
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
