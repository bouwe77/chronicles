defmodule Chronicles.StoriesTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Games, Repo, Stories}
  alias Chronicles.Accounts.Scope
  alias Chronicles.Stories.Story

  defp slugs(stories), do: Enum.map(stories, & &1.slug)

  defp touch(struct, minutes_ago) do
    at = DateTime.utc_now() |> DateTime.add(-minutes_ago, :minute) |> DateTime.truncate(:second)
    struct |> Ecto.Changeset.change(updated_at: at) |> Repo.update!()
  end

  setup do
    scope = user_scope_fixture()
    %{scope: scope}
  end

  test "the most recent activity comes first: a new version, or your last move", %{scope: scope} do
    number = story_fixture(scope, "the-number") |> touch(30)
    bearer = story_fixture(scope, "the-bearer-of-this-letter") |> touch(20)
    assert slugs(Stories.list_stories(scope)) == [bearer.slug, number.slug]

    {:ok, game, _} = Games.start_game(scope, Stories.get_story!(scope, number.slug))
    touch(game, 10)
    assert slugs(Stories.list_stories(scope)) == [number.slug, bearer.slug]
  end

  test "another player's moves don't change your order", %{scope: scope} do
    number = story_fixture(scope, "the-number", :public) |> touch(30)
    bearer = story_fixture(scope, "the-bearer-of-this-letter", :public) |> touch(20)
    other = user_scope_fixture()
    {:ok, game, _} = Games.start_game(other, Stories.get_story!(other, number.slug))
    touch(game, 10)

    assert slugs(Stories.list_stories(scope)) == [bearer.slug, number.slug]
  end

  test "tags filter the list: a story needs all of them", %{scope: scope} do
    story_fixture(scope, "the-number")
    story_fixture(scope, "the-bearer-of-this-letter")

    assert ["detective", "escape", "puzzle", "race against time", "test"] ==
             Stories.list_tags(scope)

    assert slugs(Stories.list_stories(scope, tags: ["puzzle", "test"])) == ["the-number"]
    assert Stories.list_stories(scope, tags: ["test", "escape"]) == []
  end

  test "only the author or an admin changes visibility or deletes", %{scope: scope} do
    story = story_fixture(scope, "the-number", :public)
    other = user_scope_fixture()

    assert Stories.set_visibility(other, story, :private) == {:error, :unauthorized}
    assert Stories.delete_story(other, story) == {:error, :unauthorized}

    admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()

    assert {:ok, %{visibility: :private}} =
             Stories.set_visibility(Scope.for_user(admin), story, :private)
  end

  describe "save_story/3" do
    alias Chronicles.Stories.Version

    test "a new slug makes a private story of your own", %{scope: scope} do
      assert {:ok, story} =
               Stories.save_story(scope, "my-number", Chronicles.Play.story("the-number"))

      assert story.visibility == :private
      assert story.author_id == scope.user.id
    end

    test "saving again makes a new head and drops the old one, unless a game plays it", %{
      scope: scope
    } do
      content = Chronicles.Play.story("the-number")
      {:ok, story} = Stories.save_story(scope, "my-number", content)
      first = story.head_version_id

      {:ok, story} =
        Stories.save_story(scope, "my-number", Map.put(content, "story_title", "Two"))

      refute Repo.get(Version, first)

      second = story.head_version_id
      {:ok, _game, _} = Games.start_game(scope, Stories.get_story!(scope, "my-number"))

      {:ok, story} =
        Stories.save_story(scope, "my-number", Map.put(content, "story_title", "Three"))

      assert Repo.get(Version, second), "a game still plays it"
      assert Stories.title(Repo.preload(story, :head_version)) == "Three"
    end

    test "players can't save, and nobody saves another author's story", %{scope: scope} do
      content = Chronicles.Play.story("the-number")
      {:ok, _} = Stories.save_story(scope, "my-number", content)

      assert Stories.save_story(user_scope_fixture(), "my-number", content) ==
               {:error, :unauthorized}

      player = user_fixture() |> Accounts.User.role_changeset(%{role: :player}) |> Repo.update!()

      assert Stories.save_story(Scope.for_user(player), "other", content) ==
               {:error, :unauthorized}
    end

    test "invalid content keeps the old head", %{scope: scope} do
      content = Chronicles.Play.story("the-number")
      {:ok, story} = Stories.save_story(scope, "my-number", content)

      assert {:error, %Ecto.Changeset{}} =
               Stories.save_story(scope, "my-number", Map.delete(content, "locations"))

      assert Repo.get!(Story, story.id).head_version_id == story.head_version_id
    end
  end

  test "invalid content is not saved, and the errors are on the changeset", %{scope: scope} do
    content = Map.put(Chronicles.Play.story("the-number"), "starting_location", "nowhere")

    assert {:error, changeset} = Stories.create_story(scope.user, "broken", content)

    assert errors_on(changeset).content == [
             ~s(starting_location "nowhere" is not a defined location)
           ]

    refute Repo.get_by(Story, slug: "broken")
  end

  test "deleting a story deletes every game of it, other players' too", %{scope: scope} do
    story = story_fixture(scope, "the-number", :public)
    other = user_scope_fixture()
    {:ok, game, _} = Games.start_game(other, Stories.get_story!(other, story.slug))

    assert {:ok, _} = Stories.delete_story(scope, story)
    refute Repo.get(Story, story.id)
    refute Repo.get(Games.Game, game.id)
  end
end
