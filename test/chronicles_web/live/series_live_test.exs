defmodule ChroniclesWeb.SeriesLiveTest do
  # The series in the game and story pages.
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.SeriesFixtures

  alias Chronicles.{Games, Repo}

  setup :register_and_log_in_user

  setup %{user: user} do
    scope = user_scope_fixture(user)
    Map.put(number_series_fixture(scope), :scope, scope)
  end

  test "a won game continues in the next story from the ending dialog", ctx do
    won = finished_number_game(ctx.scope, ctx.one)
    {:ok, view, _html} = live(ctx.conn, ~p"/games/#{won}")

    assert {:error, {:live_redirect, %{to: "/games/" <> id}}} =
             view |> element("#continue") |> render_click()

    sequel = Repo.get!(Games.Game, id)
    assert sequel.from_game_id == won.id
  end

  test "play again in a sequel starts from the same won game", ctx do
    won = finished_number_game(ctx.scope, ctx.one)
    {:ok, sequel, _} = Games.continue_game(ctx.scope, won)
    sequel = Games.get_game!(ctx.scope, sequel.id)

    # Away from 0 until the moves run out: a loss.
    lost =
      ["subtract 3", "subtract 2"]
      |> Stream.cycle()
      |> Enum.take(20)
      |> Enum.reduce_while(sequel, fn label, game ->
        {:ok, game, _} = Games.play(game, {:go, label})
        if game.state.ending, do: {:halt, game}, else: {:cont, game}
      end)

    assert lost.state.ending.outcome == :loss
    {:ok, view, _html} = live(ctx.conn, ~p"/games/#{lost}")

    {:error, {:live_redirect, %{to: "/games/" <> id}}} =
      view |> element("#play-again") |> render_click()

    assert Repo.get!(Games.Game, id).from_game_id == won.id
  end

  test "the story page shows the series and the chain", ctx do
    won = finished_number_game(ctx.scope, ctx.one)
    {:ok, sequel, _} = Games.continue_game(ctx.scope, won)

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.one.slug}")
    assert has_element?(view, "#series-part", "Part 1 of 2 of The Number")
    assert has_element?(view, "#continue-#{won.id}", "Continue in The Number Returns")
    assert has_element?(view, "#games-#{won.id} a[href='/games/#{sequel.id}']")

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.two.slug}")
    assert has_element?(view, "#needs-input", "This story continues The Number.")
    assert has_element?(view, "#games-#{sequel.id} a[href='/games/#{won.id}']")
  end
end
