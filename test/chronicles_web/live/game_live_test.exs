defmodule ChroniclesWeb.GameLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    %{story: story_fixture(user_scope_fixture(user))}
  end

  defp click_exit(view, label), do: view |> element("#exits button", label) |> render_click()

  test "a new game opens from the story page", %{conn: conn, story: story} do
    {:ok, view, _html} = live(conn, ~p"/stories/#{story.slug}")

    {:ok, view, _html} = view |> element("#new-game") |> render_click() |> follow_redirect(conn)

    assert has_element?(view, "#log", "Zero")
    assert has_element?(view, "#exits button", "add 2")
  end

  test "a new game plays the cues of its starting room once", %{conn: conn, user: user} do
    content =
      update_in(
        Chronicles.Play.story("the-number"),
        ["locations", Chronicles.Play.story("the-number")["starting_location"]],
        &Map.put(&1, "sideEffects", [%{"type" => "shake"}])
      )

    {:ok, story} = Chronicles.Stories.create_story(user, "shaky", content, :private)
    {:ok, view, _html} = live(conn, ~p"/stories/#{story.slug}")

    {:ok, view, _html} = view |> element("#new-game") |> render_click() |> follow_redirect(conn)
    assert_push_event(view, "cues", %{cues: ["shake"]})

    [game] = Chronicles.Games.list_games(user_scope_fixture(user), story)
    {:ok, view, _html} = live(conn, ~p"/games/#{game}")
    refute_push_event(view, "cues", _)
  end

  test "a move is saved, and the ending locks the board", %{conn: conn, user: user, story: story} do
    scope = user_scope_fixture(user)
    {:ok, game, _} = Chronicles.Games.start_game(scope, story)
    {:ok, view, _html} = live(conn, ~p"/games/#{game}")

    click_exit(view, "add 2")
    assert Chronicles.Games.get_game!(scope, game.id).state.turns == 1

    click_exit(view, "add 3")
    click_exit(view, "add 2")

    assert has_element?(view, "#ending", "You won!")
    assert has_element?(view, "#play-again")
    refute has_element?(view, "#exits")
  end

  test "the debug panel shows the version and the context", %{
    conn: conn,
    user: user,
    story: story
  } do
    scope = user_scope_fixture(user)
    {:ok, game, _} = Chronicles.Games.start_game(scope, story)
    {:ok, view, _html} = live(conn, ~p"/games/#{game}")

    assert has_element?(view, "#debug-version", "the latest")
    click_exit(view, "add 2")
    assert has_element?(view, "#debug-context", ~s("value": 2))

    {:ok, _story} =
      Chronicles.Stories.save_story(
        scope,
        story.slug,
        Map.put(story.head_version.content, "story_title", "Renamed")
      )

    {:ok, view, _html} = live(conn, ~p"/games/#{game}")
    assert has_element?(view, "#debug-version", "an older version")
  end

  test "someone else's game doesn't open", %{conn: conn} do
    other = user_scope_fixture()

    {:ok, game, _} =
      Chronicles.Games.start_game(other, story_fixture(other, "the-bearer-of-this-letter"))

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/games/#{game}") end
  end
end
