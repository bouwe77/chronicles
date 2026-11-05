defmodule ChroniclesWeb.API.SessionController do
  use ChroniclesWeb, :controller

  alias Chronicles.Accounts

  @doc "POST /api/session with `email` and `password`: a token for the other API calls."
  def create(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn |> put_status(:unauthorized) |> json(%{error: "wrong email or password"})

      user ->
        json(conn, %{token: ChroniclesWeb.APIAuth.sign(user)})
    end
  end

  def create(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "send email and password"})
end
