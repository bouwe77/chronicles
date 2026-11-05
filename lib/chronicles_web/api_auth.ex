defmodule ChroniclesWeb.APIAuth do
  @moduledoc """
  Token login for the JSON API, for tools and scripts. A token is a signed user id
  (`Phoenix.Token`), sent as `Authorization: Bearer <token>`. It is valid for a day; the
  user is looked up on every request, so a role change counts at once.
  """
  import Plug.Conn

  alias Chronicles.Accounts
  alias Chronicles.Accounts.Scope

  @salt "api token"
  @max_age 24 * 60 * 60

  def sign(user), do: Phoenix.Token.sign(ChroniclesWeb.Endpoint, @salt, user.id)

  @doc "Assigns `current_scope` from the bearer token, or answers 401."
  def require_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, id} <-
           Phoenix.Token.verify(ChroniclesWeb.Endpoint, @salt, token, max_age: @max_age),
         %Accounts.User{} = user <- Accounts.get_user(id) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "log in at POST /api/session"})
        |> halt()
    end
  end
end
