defmodule ChroniclesWeb.API.StoryControllerTest do
  use ChroniclesWeb.ConnCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup %{conn: conn} do
    user = user_fixture() |> set_password()
    %{conn: put_req_header(conn, "accept", "application/json"), user: user}
  end

  defp logged_in(conn, user) do
    token =
      conn
      |> post(~p"/api/session", %{email: user.email, password: valid_user_password()})
      |> json_response(200)
      |> Map.fetch!("token")

    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  test "without a token, nothing is answered", %{conn: conn} do
    assert conn |> get(~p"/api/stories") |> json_response(401)
  end

  test "a wrong password gets no token", %{conn: conn, user: user} do
    assert conn
           |> post(~p"/api/session", %{email: user.email, password: "wrong"})
           |> json_response(401)
  end

  test "save, read, list and delete a story", %{conn: conn, user: user} do
    conn = logged_in(conn, user)
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

  test "invalid content answers 422 with the errors", %{conn: conn, user: user} do
    content = Map.put(Chronicles.Play.story("the-number"), "starting_location", "nowhere")

    response =
      conn
      |> logged_in(user)
      |> put(~p"/api/stories/x", %{content: content})
      |> json_response(422)

    assert response["errors"] == [~s(starting_location "nowhere" is not a defined location)]
  end

  test "another author's story can't be changed", %{conn: conn, user: user} do
    story = story_fixture(user_scope_fixture(), "the-number", :public)
    conn = logged_in(conn, user)

    assert conn |> put(~p"/api/stories/#{story.slug}", %{content: %{}}) |> json_response(403)
    assert conn |> delete(~p"/api/stories/#{story.slug}") |> json_response(403)
  end
end
