defmodule ChroniclesWeb.API.StoryControllerTest do
  use ChroniclesWeb.ConnCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup %{conn: conn} do
    {user, token} = api_token_fixture()
    %{conn: put_req_header(conn, "accept", "application/json"), user: user, token: token}
  end

  defp logged_in(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  test "without a token, nothing is answered", %{conn: conn} do
    assert conn |> get(~p"/api/stories") |> json_response(401)
  end

  test "a revoked token is refused", %{conn: conn, user: user, token: token} do
    :ok = Chronicles.Accounts.delete_api_token(user)
    assert conn |> logged_in(token) |> get(~p"/api/stories") |> json_response(401)
  end

  test "save, read, list and delete a story", %{conn: conn, token: token} do
    conn = logged_in(conn, token)
    content = Chronicles.Play.story("the-number")

    saved = conn |> put(~p"/api/stories/my-number", %{content: content}) |> json_response(200)

    assert %{"slug" => "my-number", "visibility" => "private", "title" => "The Number"} =
             saved["data"]

    shown = conn |> get(~p"/api/stories/my-number") |> json_response(200)
    assert shown["data"]["content"] == content

    assert [%{"slug" => "my-number"}] =
             conn |> get(~p"/api/stories") |> json_response(200) |> Map.get("data")

    assert conn |> delete(~p"/api/stories/my-number") |> response(204)
    assert conn |> get(~p"/api/stories/my-number") |> json_response(404)
  end

  test "invalid content answers 422 with the errors", %{conn: conn, token: token} do
    content = Map.put(Chronicles.Play.story("the-number"), "starting_location", "nowhere")

    response =
      conn
      |> logged_in(token)
      |> put(~p"/api/stories/x", %{content: content})
      |> json_response(422)

    assert response["errors"] == [~s(starting_location "nowhere" is not a defined location)]
  end

  test "another author's story can't be changed", %{conn: conn, token: token} do
    story = story_fixture(user_scope_fixture(), "the-number", :public)
    conn = logged_in(conn, token)

    assert conn |> put(~p"/api/stories/#{story.slug}", %{content: %{}}) |> json_response(403)
    assert conn |> delete(~p"/api/stories/#{story.slug}") |> json_response(403)
  end
end
