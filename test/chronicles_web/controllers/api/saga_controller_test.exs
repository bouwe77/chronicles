defmodule ChroniclesWeb.API.SagaControllerTest do
  use ChroniclesWeb.ConnCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup %{conn: conn} do
    {user, token} = api_token_fixture()
    scope = Chronicles.Accounts.Scope.for_user(user)
    story_fixture(scope, "the-number")
    story_fixture(scope, "the-number-returns")

    %{conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  test "save, read, list and delete a saga", %{conn: conn} do
    body = %{title: "The Number", stories: ["the-number", "the-number-returns"]}
    saved = conn |> put(~p"/api/sagas/the-number", body) |> json_response(200)
    assert saved["data"]["stories"] == ["the-number", "the-number-returns"]

    assert conn |> get(~p"/api/sagas/the-number") |> json_response(200)

    assert [%{"slug" => "the-number"}] =
             conn |> get(~p"/api/sagas") |> json_response(200) |> Map.get("data")

    assert conn |> delete(~p"/api/sagas/the-number") |> response(204)
    assert conn |> get(~p"/api/sagas/the-number") |> json_response(404)
  end

  test "an unplayable saga answers 422 with the reasons", %{conn: conn} do
    body = %{title: "Backwards", stories: ["the-number-returns", "the-number"]}
    response = conn |> put(~p"/api/sagas/backwards", body) |> json_response(422)

    assert response["errors"] == [
             ~s(the first story "the-number-returns" needs input, so it can never start),
             ~s("the-number" has no input, so nothing links it to "the-number-returns")
           ]
  end

  test "a story in a saga can't be deleted until the saga changes", %{conn: conn} do
    body = %{title: "The Number", stories: ["the-number", "the-number-returns"]}
    conn |> put(~p"/api/sagas/the-number", body) |> json_response(200)

    response = conn |> delete(~p"/api/stories/the-number") |> json_response(422)
    assert response["errors"] == ["is a chapter of a saga; change or delete the saga first"]
  end
end
