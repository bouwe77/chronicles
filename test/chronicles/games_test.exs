defmodule Chronicles.GamesTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Games, Stories}

  setup do
    scope = user_scope_fixture()
    %{scope: scope, story: story_fixture(scope)}
  end

  test "a private story is only visible to its author", %{story: story} do
    other = user_scope_fixture()
    assert Stories.list_stories(other) == []
    assert_raise Ecto.NoResultsError, fn -> Stories.get_story!(other, story.slug) end
  end

  test "a public story is visible to everyone", %{scope: scope} do
    public = story_fixture(scope, "the-bearer-of-this-letter", :public)
    assert [%{slug: slug}] = Stories.list_stories(user_scope_fixture())
    assert slug == public.slug
  end

  test "a story needing input can't start on its own", %{scope: scope} do
    assert Games.start_game(scope, story_fixture(scope, "the-number-returns")) ==
             {:error, :needs_input}
  end

  test "every move is saved", %{scope: scope, story: story} do
    {:ok, game, _cues} = Games.start_game(scope, story)
    {:ok, _game, _cues} = Games.play(game, {:go, "add 2"})

    assert Games.get_game!(scope, game.id).state.turns == 1
    assert [%{id: id}] = Games.list_games(scope, story)
    assert id == game.id
  end

  test "a finished game is final", %{scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)

    game =
      Enum.reduce(["add 2", "add 3", "add 2"], game, fn label, game ->
        {:ok, game, _} = Games.play(game, {:go, label})
        game
      end)

    assert game.state.ending.outcome == :win
    assert Games.play(game, {:notes, "after the end"}) == {:error, :ended}
  end

  test "deleting a game deletes its version once nothing uses it", %{scope: scope, story: story} do
    alias Chronicles.Repo
    alias Chronicles.Stories.Version

    {:ok, old_game, _} = Games.start_game(scope, story)
    {:ok, head_game, _} = Games.start_game(scope, story)
    old = story.head_version

    # A new head version, as a story edit makes it.
    new = Repo.insert!(%Version{story_id: story.id, content: old.content})
    story |> Ecto.Changeset.change(head_version_id: new.id) |> Repo.update!()
    head_game = head_game |> Ecto.Changeset.change(version_id: new.id) |> Repo.update!()

    {:ok, _} = Games.delete_game(scope, old_game)
    refute Repo.get(Version, old.id)

    {:ok, _} = Games.delete_game(scope, head_game)
    assert Repo.get(Version, new.id), "the head version stays"
  end

  test "a user can't delete someone else's game", %{scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)
    assert Games.delete_game(user_scope_fixture(), game) == {:error, :unauthorized}
  end

  test "a user can't open someone else's game", %{scope: scope, story: story} do
    {:ok, game, _} = Games.start_game(scope, story)
    assert_raise Ecto.NoResultsError, fn -> Games.get_game!(user_scope_fixture(), game.id) end
  end
end
