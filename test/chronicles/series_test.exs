defmodule Chronicles.SeriesTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.SeriesFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Games, Repo, Stories}
  alias Chronicles.Accounts.Scope
  alias Chronicles.Stories.Validator

  defp content(slug), do: Chronicles.Play.story(slug)

  describe "the series checks" do
    test "The Number series is playable" do
      assert Validator.series_errors([
               {"one", content("the-number")},
               {"two", content("the-number-returns")}
             ]) == []
    end

    test "the first story can't need input, and each next one needs it" do
      assert Validator.series_errors([
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
               Validator.series_errors([
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

      assert Validator.series_errors([
               {"one", with_output.("win", %{"spare" => "{/moves}"})},
               {"two", two}
             ]) == []

      assert [~s(loss ending #) <> _] =
               Validator.series_errors([
                 {"one", with_output.("loss", %{"spare" => "{/moves}"})},
                 {"two", two}
               ])

      assert [~s(no win ending) <> _] =
               Validator.series_errors([
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

  describe "saving a series" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "a playable series is saved, with its stories in order", %{scope: scope} do
      %{series: series} = number_series_fixture(scope)
      assert Enum.map(series.entries, & &1.story.slug) == ["the-number", "the-number-returns"]
    end

    test "an unplayable series or an unknown story is refused", %{scope: scope} do
      story_fixture(scope, "the-number")
      story_fixture(scope, "the-number-returns")

      assert {:error, changeset} =
               Stories.save_series(scope, "x", %{
                 "title" => "X",
                 "stories" => ["the-number-returns"]
               })

      assert errors_on(changeset).stories == [
               ~s(the first story "the-number-returns" needs input, so it can never start)
             ]

      assert {:error, changeset} =
               Stories.save_series(scope, "x", %{"title" => "X", "stories" => ["nope"]})

      assert errors_on(changeset).stories == [~s(there is no story "nope")]
    end

    test "a story is in at most one series", %{scope: scope} do
      number_series_fixture(scope)

      assert {:error, changeset} =
               Stories.save_series(scope, "again", %{
                 "title" => "Again",
                 "stories" => ["the-number", "the-number-returns"]
               })

      assert ~s("the-number" is already in the series "the-number") in errors_on(changeset).stories
    end

    test "only its author or an admin changes a series", %{scope: scope} do
      %{series: series} = number_series_fixture(scope)
      attrs = %{"title" => "Mine", "stories" => ["the-number"]}

      assert Stories.save_series(user_scope_fixture(), "the-number", attrs) ==
               {:error, :unauthorized}

      assert Stories.delete_series(user_scope_fixture(), series) == {:error, :unauthorized}

      admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
      assert {:ok, _} = Stories.delete_series(Scope.for_user(admin), series)
    end

    test "a story a series names can't be deleted", %{scope: scope} do
      %{one: one} = number_series_fixture(scope)
      assert {:error, changeset} = Stories.delete_story(scope, one)
      assert errors_on(changeset).series_entry != []
    end

    test "a user with a story in someone else's series can't be deleted", %{scope: scope} do
      other = user_scope_fixture()
      story_fixture(scope, "the-number")

      {:ok, _} =
        Stories.create_story(other.user, "their-part", content("the-number-returns"), :public)

      {:ok, _} =
        Stories.save_series(scope, "mixed", %{
          "title" => "Mixed",
          "stories" => ["the-number", "their-part"]
        })

      assert {:error, _changeset} = Accounts.delete_user(other.user)

      # The series' author goes with their series, which frees the other user's story.
      assert {:ok, _} = Accounts.delete_user(scope.user)
      assert {:ok, _} = Accounts.delete_user(other.user)
    end
  end

  describe "continuing a game" do
    setup do
      scope = user_scope_fixture()
      Map.put(number_series_fixture(scope), :scope, scope)
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
