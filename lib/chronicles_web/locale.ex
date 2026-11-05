defmodule ChroniclesWeb.Locale do
  @moduledoc """
  Picks the language of each request and each LiveView: the user's choice on their
  account, else a visitor's choice in the session (both set by `LocaleController`), else
  the browser's `Accept-Language`, else English. The plug keeps the browser's language in
  the session too, because a LiveView has no request headers.
  """
  import Plug.Conn

  alias Chronicles.Accounts.User

  @default "en"

  @doc "The plug for the browser pipeline. Needs `current_scope`."
  def put_locale(conn, _opts) do
    conn = put_session(conn, :browser_locale, browser_locale(conn))

    Gettext.put_locale(
      ChroniclesWeb.Gettext,
      pick(conn.assigns[:current_scope], get_session(conn))
    )

    conn
  end

  @doc "The same for a LiveView: `use ChroniclesWeb, :live_view` adds it to every LiveView."
  def on_mount(:default, _params, session, socket) do
    Gettext.put_locale(ChroniclesWeb.Gettext, pick(socket.assigns[:current_scope], session))
    {:cont, socket}
  end

  defp pick(%{user: %User{locale: locale}}, _session) when is_binary(locale), do: locale
  defp pick(_scope, session), do: session["locale"] || session["browser_locale"] || @default

  # The first language in Accept-Language that the app has, in the browser's order.
  defp browser_locale(conn) do
    conn
    |> get_req_header("accept-language")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(
      &(&1
        |> String.split(";")
        |> hd()
        |> String.trim()
        |> String.slice(0, 2)
        |> String.downcase())
    )
    |> Enum.find(@default, &(&1 in User.locales()))
  end
end
