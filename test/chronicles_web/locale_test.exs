defmodule ChroniclesWeb.LocaleTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures

  alias Chronicles.Accounts
  alias Chronicles.Stories.{Sketch, Validator}

  test "a visitor gets the browser's language", %{conn: conn} do
    html =
      conn
      |> put_req_header("accept-language", "nl-NL,nl;q=0.9,en;q=0.8")
      |> get(~p"/users/log-in")
      |> html_response(200)

    assert html =~ ~s(lang="nl")
    assert html =~ "Inloggen met e-mail"

    html =
      build_conn()
      |> put_req_header("accept-language", "de-DE,fr")
      |> get(~p"/users/log-in")
      |> html_response(200)

    assert html =~ ~s(lang="en")
  end

  test "a visitor's choice wins over the browser, and the switch goes back to the page", %{
    conn: conn
  } do
    conn =
      conn
      |> put_req_header("referer", "http://localhost/users/log-in")
      |> put(~p"/locale?locale=nl")

    assert redirected_to(conn) == "/users/log-in"

    html =
      conn
      |> recycle()
      |> put_req_header("accept-language", "en")
      |> get(~p"/users/log-in")
      |> html_response(200)

    assert html =~ "Inloggen met e-mail"
  end

  test "a user's choice is kept on their account and used in LiveViews", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    conn |> put(~p"/locale?locale=nl")
    assert Accounts.get_user!(user.id).locale == "nl"

    {:ok, _view, html} =
      conn |> recycle() |> log_in_user(Accounts.get_user!(user.id)) |> live(~p"/stories")

    assert html =~ "Verhalen"
  end

  test "an unknown language changes nothing", %{conn: conn} do
    user = user_fixture()
    conn |> log_in_user(user) |> put(~p"/locale?locale=xx")
    assert Accounts.get_user!(user.id).locale == nil
  end

  test "every example sketch makes a valid story" do
    for locale <- Accounts.User.locales() do
      parsed = Sketch.parse(Sketch.example(locale))
      assert parsed.errors == [], locale
      assert Validator.errors(Sketch.content("Example", parsed)) == [], locale
    end
  end
end
