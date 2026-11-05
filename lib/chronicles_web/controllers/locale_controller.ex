defmodule ChroniclesWeb.LocaleController do
  @moduledoc """
  The language switch on the settings page. A logged-in user's choice goes on their account; a
  visitor's choice goes in the session. Then back to the page the switch was on.
  """
  use ChroniclesWeb, :controller

  alias Chronicles.Accounts
  alias Chronicles.Accounts.User

  def update(conn, %{"locale" => locale}) when is_binary(locale) do
    conn =
      if locale in User.locales() do
        with %{user: %User{} = user} <- conn.assigns.current_scope,
             do: Accounts.update_user_locale(user, %{locale: locale})

        put_session(conn, :locale, locale)
      else
        conn
      end

    redirect(conn, to: back(conn))
  end

  # The path of the page the switch was on, or the home page. Only a path, so this can't
  # send anyone to another site.
  defp back(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> _ = path, query: query} <- URI.parse(referer) do
      if query, do: path <> "?" <> query, else: path
    else
      _ -> ~p"/"
    end
  end
end
