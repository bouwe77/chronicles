defmodule ChroniclesWeb.PageControllerTest do
  use ChroniclesWeb.ConnCase

  import Chronicles.AccountsFixtures

  test "GET / opens the stories", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/")
    assert redirected_to(conn) == ~p"/stories"
  end

  test "GET / sends a visitor to log in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
