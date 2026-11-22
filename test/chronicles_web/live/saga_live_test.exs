defmodule ChroniclesWeb.SagaLiveTest do
  # Sagas in the game, story and saga pages, and on the overview.
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.SagaFixtures

  alias Chronicles.{Games, Repo, Stories}

  setup :register_and_log_in_user

  setup %{user: user} do
    scope = user_scope_fixture(user)
    Map.put(number_saga_fixture(scope), :scope, scope)
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

  test "the story page shows the saga and the chain", ctx do
    won = finished_number_game(ctx.scope, ctx.one)
    {:ok, sequel, _} = Games.continue_game(ctx.scope, won)

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.one.slug}")
    assert has_element?(view, "#saga-chapter", "Chapter 1 of 2 of the saga The Number")
    assert has_element?(view, "#continue-#{won.id}", "Continue in chapter 2: The Number Returns")
    assert has_element?(view, "#games-#{won.id} a[href='/games/#{sequel.id}']")

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.two.slug}")
    assert has_element?(view, "#needs-input", "This story continues The Number.")
    assert has_element?(view, "#previous-story[href='/stories/#{ctx.one.slug}']")
    assert has_element?(view, "#games-#{sequel.id} a[href='/games/#{won.id}']")
  end

  test "the overview shows a saga as one card with its chapters in order", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories")
    card = "#stories-saga-#{ctx.saga.id}"

    assert has_element?(view, card, "Saga by")
    assert has_element?(view, "#{card} li:nth-child(1) #saga-chapter-#{ctx.one.id}")
    assert has_element?(view, "#{card} li:nth-child(2) #saga-chapter-#{ctx.two.id}")
    refute has_element?(view, "#stories-#{ctx.one.id}")
    refute has_element?(view, "#stories-#{ctx.two.id}")
  end

  test "the overview locks a private saga once, on the card", ctx do
    card = "#stories-saga-#{ctx.saga.id}"
    {:ok, view, _html} = live(ctx.conn, ~p"/stories")
    refute has_element?(view, "#{card} .hero-lock-closed")

    {:ok, _} = Stories.set_visibility(ctx.scope, ctx.one, :private)
    {:ok, view, _html} = live(ctx.conn, ~p"/stories")
    assert has_element?(view, "#{card} > div > div > .hero-lock-closed")
    refute has_element?(view, "#{card} ol .hero-lock-closed")
  end

  describe "the saga page" do
    test "lists the chapters in order, with the user's progress", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{ctx.saga.slug}")
      assert has_element?(view, "#saga", "The Number")
      assert has_element?(view, "#chapters li:nth-child(1) a[data-status=ready]", "The Number")
      assert has_element?(view, "#chapters li:nth-child(2) a[data-status=locked]")

      finished_number_game(ctx.scope, ctx.one, :loss)
      {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{ctx.saga.slug}")
      assert has_element?(view, "#chapters li:nth-child(2) a[data-status=locked]")

      finished_number_game(ctx.scope, ctx.one)
      {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{ctx.saga.slug}")
      assert has_element?(view, "#chapters li:nth-child(1) a[data-status=won]")
      assert has_element?(view, "#chapters li:nth-child(2) a[data-status=ready]")
    end

    test "is linked from the overview and from a chapter", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/stories")
      assert has_element?(view, "#saga-link-#{ctx.saga.id}[href='/sagas/#{ctx.saga.slug}']")

      {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.two.slug}")
      assert has_element?(view, "#saga-link[href='/sagas/#{ctx.saga.slug}']")
    end

    test "is not found when the user may see none of its chapters", %{conn: conn} do
      other = user_scope_fixture()

      for {slug, from} <- [{"their-one", "the-number"}, {"their-two", "the-number-returns"}] do
        {:ok, _} = Stories.create_story(other.user, slug, Chronicles.Play.story(from), :private)
      end

      {:ok, _} =
        Stories.save_saga(other, "theirs", %{
          "title" => "Theirs",
          "stories" => ["their-one", "their-two"]
        })

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/sagas/theirs") end
      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/sagas/nope") end
    end
  end

  test "a story with input outside a saga says why it can't start", ctx do
    {:ok, _} =
      Stories.create_story(ctx.scope.user, "loose", Chronicles.Play.story("the-number-returns"))

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/loose")
    assert has_element?(view, "#needs-input", "it is in no saga")
    refute has_element?(view, "#new-game")
  end
end
