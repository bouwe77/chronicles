defmodule Chronicles.Engine do
  @moduledoc """
  The game engine: pure functions over a story version and a game state.

  The version is the story content as decoded JSON, with string keys. The game state is a
  `Chronicles.Engine.State`.

  A move returns the new state and its cues: the non-`log` side effects that fired
  (`"confetti"`, `"defeat"`, `"explosion"`, `"shake"`), for the UI to play.
  """

  alias Chronicles.Engine.{Ending, LogEntry, State}

  # Context keys the engine manages; the story's context.schema doesn't cover them.
  @reserved ~w(notes visits input)

  @doc "A fresh game, and the cues of the starting room. `input` is a series story's input."
  def new_game(version, input \\ nil) do
    start = version["starting_location"]

    context =
      (version["context"]["initial"] || %{})
      |> Map.merge(
        Map.new(version["context"]["randomize"] || %{}, fn {k, v} -> {k, Enum.random(v)} end)
      )
      |> then(&if(input, do: Map.put(&1, "input", input), else: &1))
      |> arrive(start)

    state = %State{
      location: start,
      context: context,
      carrying: version["starting_inventory"] || [],
      location_items:
        for(
          {id, loc} <- version["locations"],
          loc["items"] not in [nil, []],
          into: %{},
          do: {id, loc["items"]}
        ),
      supplies: for({id, d} <- version["supplies"] || %{}, into: %{}, do: {id, d["initial"] || 0})
    }

    state =
      append(
        state,
        Enum.map(version["openingLog"] || [], &entry(state, fill(&1, state), :outcome))
      )

    {state, cues} =
      state |> append(arrival_lines(version, state)) |> fire(here(version, state)["sideEffects"])

    {append(state, item_lines(state)), cues}
  end

  @doc """
  What the player can see and do now. Exits and actions that are hidden are left out; the
  ones that are shown but can't be used have `disabled?: true`. A finished game has none.
  The built-in wait is the action with id `:wait` and an empty label.
  """
  def view(version, %State{} = state) do
    loc = here(version, state)
    live? = is_nil(state.ending)

    %{
      exits:
        for {label, exit} <- (live? && loc["exits"]) || %{},
            holds?(state, exit["visibleWhen"]) do
          %{
            label: label,
            order: exit["order"] || 0,
            previous?: exit["to"] == state.previous_location,
            disabled?: not holds?(state, exit["enabledWhen"]),
            turn_cost: time_cost(exit)
          }
        end
        # Postgres jsonb and Elixir maps don't keep JSON key order, so ties sort by label.
        |> Enum.sort_by(&{&1.order, &1.label})
        |> Enum.map(&Map.delete(&1, :order)),
      actions:
        for {id, action} <- if(live?, do: actions_here(version, loc), else: []),
            holds?(state, action["visibleWhen"]) do
          %{
            id: id,
            label: action["description"] || "",
            disabled?: not holds?(state, action["enabledWhen"]),
            turn_cost: time_cost(action)
          }
        end,
      items:
        for item <- if(live?, do: items_here(state), else: []) do
          Map.put(item, "description", item_description(item, state.location))
        end,
      carrying:
        for item <- Enum.reverse(state.carrying) do
          Map.put(item, "description", item["descriptionWhenCarried"])
        end,
      supplies:
        for {id, d} <- version["supplies"] || %{} do
          count = Map.get(state.supplies, id, 0)
          name = if count == 1, do: d["name"], else: d["namePlural"] || d["name"] <> "s"
          %{id: id, name: name, count: count}
        end,
      notes_enabled?: version["notesEnabled"] == true,
      uses_time?: uses_time?(version)
    }
  end

  # Whether the story uses the clock at all. The UI only shows the time when it does.
  defp uses_time?(version),
    do:
      version["waitEnabled"] == true or
        has_key?(version, ~w(turnAtLeast turnAtMost turnEquals timeCost timeline))

  defp has_key?(map, keys) when is_map(map),
    do: Enum.any?(map, fn {key, value} -> key in keys or has_key?(value, keys) end)

  defp has_key?(list, keys) when is_list(list), do: Enum.any?(list, &has_key?(&1, keys))
  defp has_key?(_value, _keys), do: false

  @doc """
  Plays one command: `{:go, exit_label}`, `{:act, action_id}` (`:wait` for the built-in
  wait), `{:take, item_id}`, `{:drop, item_id}` or `{:notes, text}`.

  Returns `{:ok, state, cues}`, or `{:error, reason}` and the state stays as it was:
  `:ended` (the game is over), `:unavailable` (no such choice here, or it's disabled) or
  `:rejected` (the action would break context.schema or a supply's bounds).
  """
  def move(_version, %State{} = state, {:notes, text}),
    do: {:ok, put_in(state.context["notes"], text), []}

  def move(_version, %State{ending: %Ending{}}, _command), do: {:error, :ended}

  def move(version, state, {:go, label}) do
    exit = here(version, state)["exits"][label]

    if exit && available?(state, exit) do
      interact(version, state, exit, {:command, label}, fn state, cues, delta ->
        to = exit["to"]

        state = %{
          state
          | previous_location: state.location,
            location: to,
            context: arrive(state.context, to)
        }

        # The exit's log lines come before the arrival lines, the destination's after.
        {state, exit_cues} = fire(state, exit["sideEffects"])
        state = append(state, arrival_lines(version, state))
        {state, dest_cues} = fire(state, version["locations"][to]["sideEffects"])
        {state, rule_cues} = state |> append(item_lines(state)) |> finish_turn(version, delta > 0)
        {:ok, state, cues ++ exit_cues ++ dest_cues ++ rule_cues}
      end)
    else
      {:error, :unavailable}
    end
  end

  def move(version, state, {:act, id}) do
    {_, action} = List.keyfind(actions_here(version, here(version, state)), id, 0, {id, nil})

    if action && available?(state, action) do
      command = if id == :wait, do: {:wait, ""}, else: {:command, action["description"] || ""}
      interact(version, state, action, command, &perform(version, action, &1, &2, &3))
    else
      {:error, :unavailable}
    end
  end

  def move(version, state, {:take, id}) do
    case Enum.find(items_here(state), &(&1["id"] == id)) do
      nil ->
        {:error, :unavailable}

      item ->
        state
        |> update_in([Access.key!(:location_items), state.location], fn items ->
          Enum.reject(items, &(&1["id"] == id))
        end)
        |> carry(item)
        |> log(item["name"], :take)
        |> finish_turn(version, false)
        |> done()
    end
  end

  def move(version, state, {:drop, id}) do
    case Enum.find(state.carrying, &(&1["id"] == id)) do
      nil ->
        {:error, :unavailable}

      item ->
        %{
          state
          | carrying: List.delete(state.carrying, item),
            location_items:
              Map.update(state.location_items, state.location, [item], &(&1 ++ [item]))
        }
        |> log(item["name"], :drop)
        |> finish_turn(version, false)
        |> done()
    end
  end

  # The shared flow of an exit or action: the clock runs first (timeline events and rules
  # on each crossed turn). An ending on the way halts everything. When the world changed so
  # the choice no longer holds, it's cancelled with its interruptedText. Otherwise
  # `complete` does the choice itself.
  defp interact(version, state, choice, {type, text}, complete) do
    delta = time_cost(choice)
    logged = length(state.log)
    {state, cues} = catch_up(version, state, delta)
    # The command heads the lines of this move, stamped with the turn the clock reached.
    state = %{state | log: List.insert_at(state.log, logged, entry(state, text, type))}

    result =
      cond do
        state.ending ->
          {:ok, state, cues}

        not available?(state, choice) ->
          state =
            if text = choice["interruptedText"],
              do: log(state, fill(text, state), :outcome),
              else: state

          {state, rule_cues} = finish_turn(state, version, delta > 0)
          {:ok, state, cues ++ rule_cues}

        true ->
          complete.(state, cues, delta)
      end

    with {:ok, state, cues} <- result, do: {:ok, tidy(state), cues}
  end

  # An action's own effects, on top of the caught-up state. Context changes that break
  # context.schema, or a supply going out of its bounds, reject the whole move: nothing
  # changes, not even the clock.
  defp perform(version, action, state, cues, delta) do
    effects = action["effects"] || []

    context =
      Enum.reduce(for(%{"op" => _} = op <- effects, do: op), state.context, &patch(&2, &1))

    with true <- valid_context?(version, context),
         {:ok, supplies} <- spend(version, state.supplies, effects) do
      state = %{state | context: context, supplies: supplies}
      state = Enum.reduce(effects, state, &item_effect(version, &2, &1))
      {state, fired} = fire(state, action["sideEffects"])
      {state, rule_cues} = finish_turn(state, version, delta > 0)
      {:ok, state, cues ++ fired ++ rule_cues}
    else
      _ -> {:error, :rejected}
    end
  end

  defp done({state, cues}), do: {:ok, tidy(state), cues}

  defp tidy(state),
    do: %{state | location_items: Map.reject(state.location_items, fn {_, l} -> l == [] end)}

  ## Time

  defp time_cost(%{"timeCost" => n}) when is_number(n), do: n
  defp time_cost(_), do: 1

  # Steps the clock `delta` turns. On each turn: that turn's timeline events, then the
  # rules (except on the last turn: `finish_turn` runs those once the move is done, so they
  # see where the player ends up), then the endings, which halt the clock on that turn.
  defp catch_up(version, state, delta) do
    from = state.turns

    Enum.reduce_while((from + 1)..(from + delta)//1, {state, []}, fn step, {state, cues} ->
      state =
        version["timeline"]
        |> List.wrap()
        |> Enum.filter(&scheduled?(&1, step))
        |> Enum.reduce(%{state | turns: step}, fn event, state ->
          state = world_effects(version, state, event["effects"])
          if msg = event["message"], do: log(state, fill(msg, state), :outcome), else: state
        end)

      {state, rule_cues} =
        if step < from + delta, do: run_rules(version, state), else: {state, []}

      case ending(version, state) do
        nil -> {:cont, {state, cues ++ rule_cues}}
        ending -> {:halt, {end_game(state, ending), cues ++ rule_cues}}
      end
    end)
  end

  defp scheduled?(%{"atTurn" => at} = event, step) do
    every = event["every"]
    step == at or (is_integer(every) and every > 0 and step > at and rem(step - at, every) == 0)
  end

  # The end of a move: when the clock ticked, the rules for the last turn, then the endings.
  defp finish_turn(state, version, ticked?) do
    {state, cues} = if ticked?, do: run_rules(version, state), else: {state, []}

    case ending(version, state) do
      nil -> {state, cues}
      ending -> {end_game(state, ending), cues}
    end
  end

  # Every rule whose `when` holds (checked in order, over the state as it is by then)
  # applies its effects and fires its side effects.
  defp run_rules(version, state) do
    Enum.reduce(version["rules"] || [], {state, []}, fn rule, {state, cues} ->
      if holds?(state, rule["when"]) do
        {state, fired} =
          state |> then(&world_effects(version, &1, rule["effects"])) |> fire(rule["sideEffects"])

        {state, cues ++ fired}
      else
        {state, cues}
      end
    end)
  end

  # The first ending whose `when` holds, in story order.
  defp ending(version, state) do
    Enum.find_value(version["endings"] || [], fn e ->
      if holds?(state, e["when"]) do
        %Ending{
          outcome: if(e["outcome"] == "win", do: :win, else: :loss),
          message: fill(e["message"], state),
          turn: state.turns,
          output: e["output"]
        }
      end
    end)
  end

  defp end_game(state, ending), do: log(%{state | ending: ending}, ending.message, :outcome)

  ## Effects

  # Effects from the world (timeline events, rules). A supply can't reject them, so it
  # stays within its bounds instead.
  defp world_effects(version, state, effects) do
    Enum.reduce(effects || [], state, fn
      %{"op" => _} = op, state ->
        %{state | context: patch(state.context, op)}

      %{"supply" => id, "by" => by}, state ->
        d = version["supplies"][id] || %{}
        v = Map.get(state.supplies, id, 0) + by
        v = if d["max"], do: min(d["max"], v), else: v
        %{state | supplies: Map.put(state.supplies, id, max(d["min"] || 0, v))}

      effect, state ->
        item_effect(version, state, effect)
    end)
  end

  # Supply changes from an action: out of bounds is an error.
  defp spend(version, supplies, effects) do
    deltas = for %{"supply" => _} = e <- effects, do: e

    Enum.reduce_while(deltas, {:ok, supplies}, fn %{"supply" => id, "by" => by}, {:ok, acc} ->
      d = version["supplies"][id] || %{}
      v = Map.get(acc, id, 0) + by

      if v < (d["min"] || 0) or (d["max"] != nil and v > d["max"]),
        do: {:halt, :error},
        else: {:cont, {:ok, Map.put(acc, id, v)}}
    end)
  end

  # `give` takes the item from the room it lies in, or else from its definition, so an
  # item is never in two places. Giving a carried item or consuming an unheld one does
  # nothing. Other effects pass through.
  defp item_effect(_version, state, %{"consume" => id}),
    do: %{state | carrying: Enum.reject(state.carrying, &(&1["id"] == id))}

  defp item_effect(version, state, %{"give" => id}) do
    lying =
      Enum.find_value(state.location_items, fn {loc, items} ->
        if item = Enum.find(items, &(&1["id"] == id)), do: {loc, item}
      end)

    cond do
      Enum.any?(state.carrying, &(&1["id"] == id)) ->
        state

      lying ->
        {loc, item} = lying

        state
        |> update_in([Access.key!(:location_items), loc], &List.delete(&1, item))
        |> carry(item)

      true ->
        if item = definition(version, id), do: carry(state, item), else: state
    end
  end

  defp item_effect(_version, state, _effect), do: state

  defp carry(state, item), do: %{state | carrying: state.carrying ++ [item]}

  # An item's definition: the `items` catalog, the starting inventory, or a room.
  defp definition(version, id) do
    case version["items"] do
      %{^id => d} ->
        Map.put(d, "id", id)

      _ ->
        Enum.find(
          (version["starting_inventory"] || []) ++
            Enum.flat_map(Map.values(version["locations"]), &(&1["items"] || [])),
          &(&1["id"] == id)
        )
    end
  end

  defp valid_context?(version, context) do
    with schema when is_map(schema) <- version["context"]["schema"],
         {:ok, root} <- JSV.build(schema, default_meta: "http://json-schema.org/draft-07/schema") do
      match?({:ok, _}, JSV.validate(Map.drop(context, @reserved), root))
    else
      # No schema, or a broken one: nothing to check against.
      _ -> true
    end
  end

  # A JSON Patch op (`add`, `replace`, `remove`, or `inc` for a number delta). An op whose
  # parent is not an object is skipped, as JSON Patch does.
  defp patch(context, %{"op" => op, "path" => path} = p) do
    case patch_at(context, pointer(path), op, p["value"]) do
      {:ok, context} -> context
      :error -> context
    end
  end

  defp patch_at(map, [key], op, value) when is_map(map) do
    case op do
      "remove" -> {:ok, Map.delete(map, key)}
      "inc" -> {:ok, Map.put(map, key, if(is_number(map[key]), do: map[key], else: 0) + value)}
      _ -> {:ok, Map.put(map, key, value)}
    end
  end

  defp patch_at(map, [key | rest], op, value) when is_map(map) do
    with {:ok, inner} <- patch_at(Map.get(map, key), rest, op, value),
         do: {:ok, Map.put(map, key, inner)}
  end

  defp patch_at(_, _, _, _), do: :error

  ## Conditions

  defp holds?(_state, nil), do: true
  defp holds?(state, %{"anyOf" => conds}), do: Enum.any?(conds, &holds?(state, &1))
  defp holds?(state, %{"allOf" => conds}), do: Enum.all?(conds, &holds?(state, &1))
  defp holds?(state, %{"not" => cond}), do: not holds?(state, cond)
  defp holds?(state, %{"isCarrying" => id}), do: Enum.any?(state.carrying, &(&1["id"] == id))
  defp holds?(state, %{"at" => loc}), do: state.location == loc
  defp holds?(state, %{"turnAtLeast" => n}), do: state.turns >= n
  defp holds?(state, %{"turnAtMost" => n}), do: state.turns <= n
  defp holds?(state, %{"turnEquals" => n}), do: state.turns == n
  # Before the `path` clause: both use comparator keys such as `atLeast`.
  defp holds?(state, %{"supply" => id} = cond),
    do: compare(Map.get(state.supplies, id, 0), cond)

  defp holds?(state, %{"path" => path} = cond) do
    value = get_path(state.context, path)

    if Map.has_key?(cond, "equals"),
      do: value == cond["equals"],
      else: is_number(value) and compare(value, cond)
  end

  defp compare(v, %{"atLeast" => n}), do: v >= n
  defp compare(v, %{"atMost" => n}), do: v <= n
  defp compare(v, %{"greaterThan" => n}), do: v > n
  defp compare(v, %{"lessThan" => n}), do: v < n
  defp compare(v, %{"equals" => n}), do: v == n

  defp available?(state, choice),
    do: holds?(state, choice["visibleWhen"]) and holds?(state, choice["enabledWhen"])

  ## Locations, items, log

  defp here(version, state), do: version["locations"][state.location] || %{}

  # The actions shown in a location, in order: its own, then the built-in wait.
  defp actions_here(version, loc) do
    actions = version["actions"] || %{}
    own = for id <- loc["actions"] || [], Map.has_key?(actions, id), do: {id, actions[id]}
    wait = if version["waitEnabled"], do: [{:wait, %{}}], else: []
    Enum.sort_by(own, fn {_, a} -> a["order"] || 0 end) ++ wait
  end

  # The items lying here, except the ones still hidden behind `availableWhen`.
  defp items_here(state) do
    state.location_items
    |> Map.get(state.location, [])
    |> Enum.filter(&holds?(state, &1["availableWhen"]))
  end

  defp item_description(item, loc), do: item["descriptionByLocation"][loc] || item["description"]

  # The room name as a heading, then its arrivalText (picked by visit number when it's a
  # list; the last one repeats), else its description.
  defp arrival_lines(version, state) do
    id = state.location
    loc = here(version, state)
    texts = List.wrap(loc["arrivalText"] || loc["description"] || id)
    text = Enum.at(texts, max(min(visits(state.context, id), length(texts)) - 1, 0))
    [entry(state, loc["name"] || id, :location), entry(state, fill(text, state), :outcome)]
  end

  # The descriptions of the items present, written into the log on arrival.
  defp item_lines(state) do
    for item <- items_here(state),
        text <- [item_description(item, state.location)],
        text not in [nil, ""],
        do: entry(state, fill(text, state), :outcome)
  end

  # Fires the side effects whose `when` holds: `log` ones are written to the log, the
  # others are returned as cues.
  defp fire(state, effects) do
    fired = Enum.filter(effects || [], &holds?(state, &1["when"]))

    lines =
      for %{"type" => "log", "text" => text} <- fired,
          text,
          do: entry(state, fill(text, state), :outcome)

    {append(state, lines), for(%{"type" => type} <- fired, type != "log", do: type)}
  end

  defp entry(state, text, type), do: %LogEntry{turn: state.turns, type: type, text: text}
  defp log(state, text, type), do: append(state, [entry(state, text, type)])
  defp append(state, lines), do: %{state | log: state.log ++ lines}

  ## Context

  defp visits(context, loc) do
    case context do
      %{"visits" => %{^loc => n}} when is_number(n) -> n
      _ -> 0
    end
  end

  defp arrive(context, loc) do
    visits = if is_map(context["visits"]), do: context["visits"], else: %{}
    Map.put(context, "visits", Map.put(visits, loc, visits(context, loc) + 1))
  end

  # `{/json/pointer}` becomes that context value, `{supply:id}` the amount carried.
  defp fill(text, state) do
    Regex.replace(~r/\{(\/[^{}\s]*|supply:[^{}\s]+)\}/, text, fn
      _, "supply:" <> id -> to_string(Map.get(state.supplies, id, 0))
      _, path -> text_of(get_path(state.context, path))
    end)
  end

  defp text_of(nil), do: ""
  defp text_of(v) when is_binary(v) or is_number(v) or is_boolean(v), do: to_string(v)
  defp text_of(v), do: Jason.encode!(v)

  defp get_path(context, path) do
    Enum.reduce(pointer(path), context, fn
      key, map when is_map(map) ->
        Map.get(map, key)

      key, list when is_list(list) ->
        case Integer.parse(key) do
          {i, ""} -> Enum.at(list, i)
          _ -> nil
        end

      _, _ ->
        nil
    end)
  end

  defp pointer(path) do
    path
    |> String.split("/")
    |> Enum.drop(1)
    |> Enum.map(&(&1 |> String.replace("~1", "/") |> String.replace("~0", "~")))
  end
end
