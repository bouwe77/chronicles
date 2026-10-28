defmodule Chronicles.Play do
  @moduledoc """
  Drives `Chronicles.Engine` by button label, the way a player clicks. A port of
  adventure-game's `app/sim/play.mjs`. Every step returns a new `%{version, state}`.
  """

  alias Chronicles.Engine

  @fixtures Path.expand("../fixtures/stories", __DIR__)

  # A story's head version, exported from adventure-game into test/fixtures/stories.
  def story(id), do: @fixtures |> Path.join("#{id}.json") |> File.read!() |> Jason.decode!()

  # `setup` may change the fresh game state before the first move.
  def start(version, opts \\ []) do
    {state, _cues} = Engine.new_game(version, opts[:input])
    setup = Keyword.get(opts, :setup, & &1)
    %{version: version, state: setup.(state)}
  end

  def view(game), do: Engine.view(game.version, game.state)

  def exit(game, label), do: click(game, :exits, label, fn _ -> {:go, label} end)

  def act(game, label), do: click(game, :actions, label, &{:act, &1.id})

  def wait_until(game, turn) do
    if game.state["turns"] < turn, do: game |> act("Wait") |> wait_until(turn), else: game
  end

  def take(game, name) do
    item = Enum.find(view(game).items, &(&1["name"] == name)) || raise "no item #{name} here"
    move!(game, {:take, item["id"]})
  end

  # How many log lines match `regex`.
  def count(game, regex), do: Enum.count(game.state["log"], &(&1["text"] =~ regex))

  # The game after `fun`, and the log lines `fun` added.
  def during(game, fun) do
    after_fun = fun.(game)

    {after_fun,
     after_fun.state["log"] |> Enum.drop(length(game.state["log"])) |> Enum.map(& &1["text"])}
  end

  defp click(game, kind, label, command) do
    buttons = Map.fetch!(view(game), kind)

    case Enum.find(buttons, &(&1.label == label)) do
      %{disabled?: false} = button ->
        move!(game, command.(button))

      _ ->
        available = Enum.map_join(buttons, ", ", &"#{&1.label}#{if &1.disabled?, do: " (off)"}")
        raise "#{kind} #{inspect(label)} not available at t#{game.state["turns"]}: #{available}"
    end
  end

  defp move!(game, command) do
    case Engine.move(game.version, game.state, command) do
      {:ok, state, _cues} -> %{game | state: state}
      {:error, reason} -> raise "#{inspect(command)} failed: #{reason}"
    end
  end
end
