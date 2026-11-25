defmodule Chronicles.SagaFixtures do
  @moduledoc "The Number saga for tests: two stories, where a win of the first unlocks the second."

  import Chronicles.StoriesFixtures

  alias Chronicles.{Games, Stories}

  def number_saga_fixture(scope, visibility \\ :public) do
    one = story_fixture(scope, "the-number", visibility)
    two = story_fixture(scope, "the-number-returns", visibility)

    {:ok, saga} =
      Stories.save_saga(scope, "the-number", %{
        "title" => "The Number",
        "stories" => [one.slug, two.slug]
      })

    %{saga: saga, one: one, two: two}
  end

  # A finished game of The Number: the fastest win, or a loss.
  def finished_number_game(scope, story, outcome \\ :win) do
    exits =
      if outcome == :win,
        do: ["add_2", "add_3", "add_2"],
        else: ["add_3", "add_2", "add_3", "add_2", "add_3", "add_2"]

    {:ok, game, _} = Games.start_game(scope, story)

    Enum.reduce(exits, game, fn id, game ->
      {:ok, game, _} = Games.play(game, {:go, id})
      game
    end)
  end
end
