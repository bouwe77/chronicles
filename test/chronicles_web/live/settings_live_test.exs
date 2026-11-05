defmodule ChroniclesWeb.SettingsLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures

  test "a visitor can open the settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#language-setting #locale-nl")
    assert has_element?(view, "#theme-setting")
  end

  test "marks the user's language as current", %{conn: conn} do
    user = user_fixture()
    {:ok, _} = Chronicles.Accounts.update_user_locale(user, %{locale: "nl"})

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/settings")

    assert has_element?(view, "#locale-nl[aria-current]")
    refute has_element?(view, "#locale-en[aria-current]")
  end
end
