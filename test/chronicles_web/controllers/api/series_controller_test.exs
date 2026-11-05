defmodule ChroniclesWeb.API.SeriesControllerTest do
  use ChroniclesWeb.ConnCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup %{conn: conn} do
    user = user_fixture() |> set_password()
    scope = Chronicles.Accounts.Scope.for_user(user)
    story_fixture(scope, "the-number")
    story_fixture(scope, "the-number-returns")

    token =
      conn
      |> post(~p"/api/session", %{email: user.email, password: valid_user_password()})
      |> json_response(200)
      |> Map.fetch!("token")

    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "save, read, list and delete a series", %{conn: conn} do
    body = %{title: "The Number", stories: ["the-number", "the-number-returns"]}
    saved = conn |> put(~p"/api/series/the-number", body) |> json_response(200)
    assert saved["data"]["stories"] == ["the-number", "the-number-returns"]

    assert conn |> get(~p"/api/series/the-number") |> json_response(200)

    assert [%{"slug" => "the-number"}] =
             conn |> get(~p"/api/series") |> json_response(200) |> Map.get("data")

    assert conn |> delete(~p"/api/series/the-number") |> response(204)
    assert conn |> get(~p"/api/series/the-number") |> json_response(404)
  end

  test "an unplayable series answers 422 with the reasons", %{conn: conn} do
    body = %{title: "Backwards", stories: ["the-number-returns", "the-number"]}
    response = conn |> put(~p"/api/series/backwards", body) |> json_response(422)

    assert response["errors"] == [
             ~s(the first story "the-number-returns" needs input, so it can never start),
             ~s("the-number" has no input, so nothing links it to "the-number-returns")
           ]
  end

  test "a story in a series can't be deleted until the series changes", %{conn: conn} do
    body = %{title: "The Number", stories: ["the-number", "the-number-returns"]}
    conn |> put(~p"/api/series/the-number", body) |> json_response(200)

    response = conn |> delete(~p"/api/stories/the-number") |> json_response(422)
    assert response["errors"] == ["is part of a series; change or delete the series first"]
  end
end
