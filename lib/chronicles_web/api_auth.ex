defmodule ChroniclesWeb.APIAuth do
  @moduledoc """
  Token login for the JSON API, for tools and scripts. A user with API access creates a
  token on the account page and sends it as `Authorization: Bearer <token>`. The token is
  looked up on every request, so revoking it or turning off API access counts at once.
  """
  import Plug.Conn

  alias Chronicles.Accounts
  alias Chronicles.Accounts.Scope

  @doc "Assigns `current_scope` from the bearer token, or answers 401."
  def require_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "send an API token from your account page"})
        |> halt()
    end
  end
end
