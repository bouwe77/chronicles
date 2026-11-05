defmodule Chronicles.SeriesFixtures do
  @moduledoc "The Number series for tests: two stories, where a win of the first unlocks the second."

  import Chronicles.StoriesFixtures

  alias Chronicles.{Games, Stories}

  def number_series_fixture(scope, visibility \\ :public) do
    one = story_fixture(scope, "the-number", visibility)
    two = story_fixture(scope, "the-number-returns", visibility)

    {:ok, series} =
      Stories.save_series(scope, "the-number", %{
        "title" => "The Number",
        "stories" => [one.slug, two.slug]
      })

    %{series: series, one: one, two: two}
  end

  # A finished game of The Number: the fastest win, or a loss.
  def finished_number_game(scope, story, outcome \\ :win) do
    exits =
      if outcome == :win,
        do: ["add 2", "add 3", "add 2"],
        else: ["add 3", "add 2", "add 3", "add 2", "add 3", "add 2"]

    {:ok, game, _} = Games.start_game(scope, story)

    Enum.reduce(exits, game, fn label, game ->
      {:ok, game, _} = Games.play(game, {:go, label})
      game
    end)
  end
end
