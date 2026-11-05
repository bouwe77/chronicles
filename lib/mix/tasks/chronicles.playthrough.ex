defmodule Mix.Tasks.Chronicles.Playthrough do
  @shortdoc "Plays scripted paths through a story file with the real engine"

  @moduledoc """
  Plays scripted paths through a story's content with `Chronicles.Engine`, and reports
  which ending each path reaches. The content is checked first, the same as a save.

      mix chronicles.playthrough story.json paths.json

  `paths.json` maps a path name to its steps and the expected result:

      {"shortest win": {"steps": ["go:hall", "take:key", "open_door"], "expect": "win"}}

  A step is `go:<exit label or room id>`, `take:<item id>`, `drop:<item id>`, `wait`, or
  an action key. `expect` is `win`, `loss`, `none` (no ending yet) or `broke` (a step is
  not possible). A path may give `input`, for a story that takes input. The task fails
  when any path doesn't end as expected.
  """
  use Mix.Task

  alias Chronicles.Engine
  alias Chronicles.Stories.Validator

  @requirements ["compile"]

  @impl Mix.Task
  def run([story_file, paths_file]) do
    content = story_file |> File.read!() |> Jason.decode!() |> Map.delete("story_id")
    paths = paths_file |> File.read!() |> Jason.decode!()

    case Validator.errors(content) do
      [] -> :ok
      errors -> Mix.raise("The story is not valid:\n" <> Enum.join(errors, "\n"))
    end

    failed =
      for {name, path} <- paths, reduce: 0 do
        failed ->
          {result, detail} = play(content, path["steps"], path["input"])
          ok? = result == path["expect"]
          Mix.shell().info("#{if ok?, do: "ok  ", else: "FAIL"}  #{name}: #{result} #{detail}")
          if ok?, do: failed, else: failed + 1
      end

    if failed > 0, do: Mix.raise("#{failed} of #{map_size(paths)} paths did not end as expected")
  end

  def run(_), do: Mix.raise("Usage: mix chronicles.playthrough STORY.json PATHS.json")

  defp play(content, steps, input) do
    {state, _cues} = Engine.new_game(content, input)

    steps
    |> Enum.with_index(1)
    |> Enum.reduce_while(state, fn {step, i}, state ->
      case Engine.move(content, state, command(content, state, step)) do
        {:ok, state, _cues} -> {:cont, state}
        {:error, reason} -> {:halt, {:broke, i, step, reason, state}}
      end
    end)
    |> result(content)
  end

  defp result({:broke, i, step, reason, state}, content) do
    view = Engine.view(content, state)
    exits = Enum.map_join(view.exits, ", ", &label/1)
    actions = Enum.map_join(view.actions, ", ", &"#{&1.id}#{if &1.disabled?, do: " (off)"}")

    {"broke",
     "at step #{i} #{inspect(step)} (#{reason}) in #{state.location} at turn #{state.turns}; " <>
       "exits: #{exits}; actions: #{actions}"}
  end

  defp result(state, _content) do
    case state.ending do
      nil -> {"none", "in #{state.location} at turn #{state.turns}"}
      ending -> {to_string(ending.outcome), "at turn #{ending.turn}: #{ending.message}"}
    end
  end

  defp label(exit), do: "#{exit.label}#{if exit.disabled?, do: " (off)"}"

  defp command(_content, _state, "wait"), do: {:act, :wait}
  defp command(_content, _state, "take:" <> id), do: {:take, id}
  defp command(_content, _state, "drop:" <> id), do: {:drop, id}

  # An exit by its label, or else by the room it leads to.
  defp command(content, state, "go:" <> target) do
    exits = content["locations"][state.location]["exits"]

    if Map.has_key?(exits, target) do
      {:go, target}
    else
      case Enum.find(exits, fn {_label, exit} -> exit["to"] == target end) do
        {label, _exit} -> {:go, label}
        nil -> {:go, target}
      end
    end
  end

  defp command(_content, _state, action), do: {:act, action}
end
