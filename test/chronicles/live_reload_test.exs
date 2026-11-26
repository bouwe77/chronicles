defmodule Chronicles.LiveReloadTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.SagaFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Games, Play, Stories}
  alias Chronicles.Games.Game

  # A saga test makes its own the-number.
  setup tags do
    scope = user_scope_fixture()
    if tags[:saga], do: %{scope: scope}, else: %{scope: scope, story: story_fixture(scope)}
  end

  defp play(game, commands) do
    Enum.reduce(commands, game, fn command, game ->
      {:ok, game, _} = Games.play(game, command)
      game
    end)
  end

  # Saves the-number, changed by `fun`, as the story's new head version.
  defp new_version(scope, story, fun) do
    {:ok, _} = Stories.save_story(scope, story.slug, fun.(Play.story("the-number")))
  end

  # The-number with a random value "room" that is "a" or "b".
  defp with_room(content, choices) do
    content
    |> put_in(["context", "initial", "room"], hd(choices))
    |> put_in(["context", "randomize"], %{"room" => choices})
  end

  test "an author's game records its moves and picks, but not its notes", %{
    scope: scope,
    story: story
  } do
    new_version(scope, story, &with_room(&1, ["a", "b"]))
    {:ok, game, _} = Games.start_game(scope, Stories.get_story!(scope, story.slug))
    game = play(game, [{:go, "add_2"}, {:notes, "hm"}, {:go, "add_3"}])

    assert game.state.commands == [["go", "add_2"], ["go", "add_3"]]
    assert game.state.picks == %{"room" => game.state.context["room"]}
  end

  test "another player's game records nothing", %{story: story} do
    {:ok, game, _} = Games.start_game(user_scope_fixture(), story)
    game = play(game, [{:go, "add_2"}])

    assert game.state.commands == nil
    assert Games.reload(user_scope_fixture(), game) == {:error, :not_recording}
  end

  test "a reload replays every move on the new version, and keeps the notes", %{
    scope: scope,
    story: story
  } do
    new_version(scope, story, &Map.put(&1, "waitEnabled", true))
    {:ok, game, _} = Games.start_game(scope, Stories.get_story!(scope, story.slug))
    game = play(game, [{:go, "add_2"}, {:notes, "hm"}, {:act, :wait}, {:go, "add_3"}])
    assert ["wait"] in game.state.commands

    # A new button text doesn't change the exit.
    new_version(scope, story, fn content ->
      content
      |> Map.put("waitEnabled", true)
      |> put_in(["locations", "zero", "exits", "add_2", "name"], "+2")
    end)

    assert {:ok, new, :replayed} = Games.reload(scope, game)
    assert new.state.commands == game.state.commands
    assert new.state.context["value"] == game.state.context["value"]
    assert new.state.context["notes"] == "hm"
    assert new.version_id != game.version_id
    refute Repo.get(Game, game.id)
  end

  test "a reload stops at a move that no longer works", %{scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)
    game = play(game, [{:go, "add_2"}, {:go, "add_3"}])

    new_version(scope, story, fn content ->
      {_, content} = pop_in(content, ["locations", "plus_two", "exits", "add_3"])
      content
    end)

    assert {:ok, new, {:stopped, 1, 2, ["go", "add_3"]}} = Games.reload(scope, game)
    assert new.state.location == "plus_two"
    assert new.state.commands == [["go", "add_2"]]
  end

  test "a reload keeps the old picks while they're allowed", %{scope: scope, story: story} do
    new_version(scope, story, &with_room(&1, ["a", "b"]))
    {:ok, game, _} = Games.start_game(scope, Stories.get_story!(scope, story.slug))
    room = game.state.context["room"]

    new_version(scope, story, &with_room(&1, ["a", "b", "c"]))

    assert {:ok, new, :replayed} = Games.reload(scope, game)
    assert new.state.context["room"] == room
  end

  test "a pick that is no longer allowed starts a fresh game", %{scope: scope, story: story} do
    new_version(scope, story, &with_room(&1, ["a", "b"]))
    {:ok, game, _} = Games.start_game(scope, Stories.get_story!(scope, story.slug))
    game = play(game, [{:go, "add_2"}])

    new_version(scope, story, &with_room(&1, ["c", "d"]))

    assert {:ok, new, {:new_pick, "room", room}} = Games.reload(scope, game)
    assert room == game.state.context["room"]
    assert new.state.context["room"] in ["c", "d"]
    assert new.state.turns == 0
  end

  test "a reload shows an ending the new version reaches earlier", %{scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)
    game = play(game, [{:go, "add_2"}, {:go, "add_3"}])

    # The first win is at 5 now, which the two moves reach.
    new_version(
      scope,
      story,
      &put_in(&1, ["endings", Access.at(0), "when", "allOf", Access.at(0), "equals"], 5)
    )

    assert {:ok, new, :replayed} = Games.reload(scope, game)
    assert new.state.ending.outcome == :win
  end

  @tag :saga
  test "a reloaded sequel still continues its game", %{scope: scope} do
    %{one: one, two: two} = number_saga_fixture(scope)
    finished = finished_number_game(scope, one)
    {:ok, game, _} = Games.continue_game(scope, finished)

    {:ok, _} = Stories.save_story(scope, two.slug, Play.story("the-number-returns"))

    assert {:ok, new, :replayed} = Games.reload(scope, game)
    assert new.from_game_id == finished.id
  end

  test "a save of several stories that fails broadcasts nothing", %{scope: scope, story: story} do
    Stories.subscribe_to_versions(story.id)
    other = story_fixture(scope, "the-number-returns")

    assert {:error, _} =
             Stories.save_stories(scope, [
               {story, Play.story("the-number")},
               {other, %{"story_title" => "broken"}}
             ])

    refute_received {:new_version, _}

    {:ok, _} = Stories.save_stories(scope, [{story, Play.story("the-number")}])
    assert_received {:new_version, id}
    assert id == story.id
  end
end
