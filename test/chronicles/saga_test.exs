defmodule Chronicles.SagaTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.SagaFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Games, Repo, Stories}
  alias Chronicles.Accounts.Scope
  alias Chronicles.Stories.Validator

  defp content(slug), do: Chronicles.Play.story(slug)

  describe "the saga checks" do
    test "The Number saga is playable" do
      assert Validator.saga_errors([
               {"one", content("the-number")},
               {"two", content("the-number-returns")}
             ]) == []
    end

    test "the first story can't need input, and each next one needs it" do
      assert Validator.saga_errors([
               {"two", content("the-number-returns")},
               {"one", content("the-number")}
             ]) == [
               ~s(the first story "two" needs input, so it can never start),
               ~s("one" has no input, so nothing links it to "two")
             ]
    end

    test "a win must unlock the next story, and a loss must not" do
      one = content("the-number")

      endings =
        for ending <- one["endings"] do
          if ending["outcome"] == "win",
            do: Map.delete(ending, "output"),
            else: Map.put(ending, "output", %{"spare" => 0})
        end

      assert [
               ~s(no win ending of "one" has output that "two" accepts),
               ~s(loss ending #) <> _
             ] =
               Validator.saga_errors([
                 {"one", Map.put(one, "endings", endings)},
                 {"two", content("the-number-returns")}
               ])
    end

    test "an output placeholder counts as unknown until the game ends" do
      one = content("the-number")
      two = content("the-number-returns")

      with_output = fn outcome, output ->
        endings =
          for e <- one["endings"],
              do: if(e["outcome"] == outcome, do: Map.put(e, "output", output), else: e)

        Map.put(one, "endings", endings)
      end

      assert Validator.saga_errors([
               {"one", with_output.("win", %{"spare" => "{/moves}"})},
               {"two", two}
             ]) == []

      assert [~s(loss ending #) <> _] =
               Validator.saga_errors([
                 {"one", with_output.("loss", %{"spare" => "{/moves}"})},
                 {"two", two}
               ])

      assert [~s(no win ending) <> _] =
               Validator.saga_errors([
                 {"one", with_output.("win", %{"other" => "{/moves}"})},
                 {"two", two}
               ])

      refute Validator.accepts_input?(two, %{"spare" => 5})
    end

    test "input is accepted when the output passes input.schema" do
      two = content("the-number-returns")
      assert Validator.accepts_input?(two, %{"spare" => 2})
      refute Validator.accepts_input?(two, %{"spare" => "lots"})
      refute Validator.accepts_input?(two, nil)
      refute Validator.accepts_input?(content("the-number"), %{"spare" => 2})
    end
  end

  describe "saving a saga" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "a playable saga is saved, with its stories in order", %{scope: scope} do
      %{saga: saga} = number_saga_fixture(scope)
      assert Enum.map(saga.chapters, & &1.story.slug) == ["the-number", "the-number-returns"]
    end

    test "an unplayable saga or an unknown story is refused", %{scope: scope} do
      story_fixture(scope, "the-number")
      story_fixture(scope, "the-number-returns")

      assert {:error, changeset} =
               Stories.save_saga(scope, "x", %{
                 "title" => "X",
                 "stories" => ["the-number-returns"]
               })

      assert errors_on(changeset).stories == [
               ~s(the first story "the-number-returns" needs input, so it can never start)
             ]

      assert {:error, changeset} =
               Stories.save_saga(scope, "x", %{"title" => "X", "stories" => ["nope"]})

      assert errors_on(changeset).stories == [~s(there is no story "nope")]
    end

    test "a story is in at most one saga", %{scope: scope} do
      number_saga_fixture(scope)

      assert {:error, changeset} =
               Stories.save_saga(scope, "again", %{
                 "title" => "Again",
                 "stories" => ["the-number", "the-number-returns"]
               })

      assert ~s("the-number" is already in the saga "the-number") in errors_on(changeset).stories
    end

    test "only its author or an admin changes a saga", %{scope: scope} do
      %{saga: saga} = number_saga_fixture(scope)
      attrs = %{"title" => "Mine", "stories" => ["the-number"]}

      assert Stories.save_saga(user_scope_fixture(), "the-number", attrs) ==
               {:error, :unauthorized}

      assert Stories.delete_saga(user_scope_fixture(), saga) == {:error, :unauthorized}

      admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
      assert {:ok, _} = Stories.delete_saga(Scope.for_user(admin), saga)
    end

    test "a story a saga names can't be deleted", %{scope: scope} do
      %{one: one} = number_saga_fixture(scope)
      assert {:error, changeset} = Stories.delete_story(scope, one)
      assert errors_on(changeset).chapter != []
    end

    test "a user with a story in someone else's saga can't be deleted", %{scope: scope} do
      other = user_scope_fixture()
      story_fixture(scope, "the-number", :public)

      {:ok, _} =
        Stories.create_story(other.user, "their-part", content("the-number-returns"), :public)

      {:ok, _} =
        Stories.save_saga(scope, "mixed", %{
          "title" => "Mixed",
          "stories" => ["the-number", "their-part"]
        })

      assert {:error, _changeset} = Accounts.delete_user(other.user)

      # The saga's author goes with their saga, which frees the other user's story.
      assert {:ok, _} = Accounts.delete_user(scope.user)
      assert {:ok, _} = Accounts.delete_user(other.user)
    end

    test "the stories of a saga must share their visibility", %{scope: scope} do
      story_fixture(scope, "the-number", :public)
      story_fixture(scope, "the-number-returns", :private)

      assert {:error, changeset} =
               Stories.save_saga(scope, "x", %{
                 "title" => "X",
                 "stories" => ["the-number", "the-number-returns"]
               })

      assert errors_on(changeset).stories == ["the stories must all be public or all be private"]
    end

    test "changing the visibility of a story changes its whole saga", %{scope: scope} do
      %{one: one, two: two} = number_saga_fixture(scope, :private)

      assert {:ok, %{visibility: :public}} = Stories.set_visibility(scope, two, "public")
      assert Repo.get!(Stories.Story, one.id).visibility == :public
      assert Repo.get!(Stories.Story, two.id).visibility == :public
    end

    test "only someone who manages every story of a saga changes its visibility", %{
      scope: scope
    } do
      other = user_scope_fixture()
      mine = story_fixture(scope, "the-number", :public)

      {:ok, _} =
        Stories.create_story(other.user, "their-part", content("the-number-returns"), :public)

      {:ok, _} =
        Stories.save_saga(scope, "mixed", %{
          "title" => "Mixed",
          "stories" => ["the-number", "their-part"]
        })

      assert Stories.set_visibility(scope, mine, :private) == {:error, :unauthorized}
      assert Repo.get!(Stories.Story, mine.id).visibility == :public
    end

    test "saving a chapter that breaks its saga gives a warning", %{scope: scope} do
      %{one: one} = number_saga_fixture(scope)
      assert Stories.saga_warnings(one) == []

      content =
        Map.update!(one.head_version.content, "endings", fn endings ->
          Enum.map(endings, &Map.delete(&1, "output"))
        end)

      {:ok, saved} = Stories.save_story(scope, one.slug, content)
      assert [~s(saga "the-number": ) <> _ | _] = Stories.saga_warnings(saved)
    end

    # Stories in the same order as every other test, or async tests can deadlock on the
    # unique slugs.
    test "a story with input outside a saga gives a warning", %{scope: scope} do
      assert Stories.saga_warnings(story_fixture(scope, "the-number")) == []

      assert Stories.saga_warnings(story_fixture(scope, "the-number-returns")) == [
               "the story takes input but is in no saga, so no game of it can start"
             ]
    end
  end

  describe "continuing a game" do
    setup do
      scope = user_scope_fixture()
      Map.put(number_saga_fixture(scope), :scope, scope)
    end

    test "a won game continues in the next story, with its output as input", ctx do
      won = finished_number_game(ctx.scope, ctx.one)
      assert Games.sequel(ctx.scope, won).id == ctx.two.id

      {:ok, sequel, _cues} = Games.continue_game(ctx.scope, won)
      assert sequel.from_game_id == won.id
      assert sequel.state.context["input"] == %{"spare" => 3}
    end

    test "a lost or unfinished game has no sequel", ctx do
      lost = finished_number_game(ctx.scope, ctx.one, :loss)
      assert Games.sequel(ctx.scope, lost) == nil
      assert Games.continue_game(ctx.scope, lost) == {:error, :no_sequel}

      {:ok, playing, _} = Games.start_game(ctx.scope, ctx.one)
      assert Games.sequel(ctx.scope, playing) == nil
    end

    test "only your own game can be continued", ctx do
      won = finished_number_game(ctx.scope, ctx.one)
      assert Games.continue_game(user_scope_fixture(), won) == {:error, :no_sequel}
    end
  end
end
