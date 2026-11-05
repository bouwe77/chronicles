defmodule ChroniclesWeb.StoryLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Games, Repo}
  alias Chronicles.Stories.Story

  setup :register_and_log_in_user

  setup %{user: user} do
    scope = user_scope_fixture(user)
    %{scope: scope, story: story_fixture(scope, "the-number")}
  end

  test "the author manages the story; another player doesn't", %{conn: conn, story: story} do
    {:ok, view, _html} = live(conn, ~p"/stories/#{story.slug}")
    assert has_element?(view, "#manage")

    view |> element("#make-public") |> render_click()
    assert Repo.get!(Story, story.id).visibility == :public
    assert has_element?(view, "#make-private")

    other_conn = log_in_user(build_conn(), user_fixture())
    {:ok, other_view, _html} = live(other_conn, ~p"/stories/#{story.slug}")
    refute has_element?(other_view, "#manage")
  end

  test "deleting the story goes back to the list", %{conn: conn, story: story} do
    {:ok, view, _html} = live(conn, ~p"/stories/#{story.slug}")

    assert {:error, {:live_redirect, %{to: "/stories"}}} =
             view |> element("#delete-story") |> render_click()

    refute Repo.get(Story, story.id)
  end

  test "a game can be deleted", %{conn: conn, scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)
    {:ok, view, _html} = live(conn, ~p"/stories/#{story.slug}")

    view |> element("#delete-game-#{game.id}") |> render_click()

    refute has_element?(view, "#games-#{game.id}")
    assert Games.list_games(scope, story) == []
  end
end
