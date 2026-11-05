defmodule Chronicles.Stories.Validator do
  @moduledoc """
  Checks a story's content before it is saved, and returns readable errors (none means
  valid).

  First the shape, against the JSON Schema in `priv/schemas/version.json`. Then the rules a
  schema can't express: exits and conditions name real locations, items and supplies,
  effects only change declared context keys, the engine's reserved keys stay untouched,
  placeholders show something real, and so on. The rules assume a valid shape, so they only
  run once the shape passes.
  """

  @draft7 "http://json-schema.org/draft-07/schema"
  @schema_path Path.expand("../../../priv/schemas/version.json", __DIR__)
  @external_resource @schema_path
  @schema @schema_path |> File.read!() |> Jason.decode!() |> JSV.build!(default_meta: @draft7)
  # What a valid JSON Schema looks like, for the schemas inside a story.
  @meta_schema JSV.build!(%{"$ref" => @draft7 <> "#"}, default_meta: @draft7)

  # Context keys the engine manages, which a story may not declare or change.
  @reserved %{
    "notes" => "managed by the notes feature",
    "visits" => "the engine counts arrivals there",
    "input" => "the game's input lives there"
  }

  @placeholder ~r/\{(\/[^{}\s]*|supply:[^{}\s]+)\}/

  @doc "The errors in a story's content. An empty list means it's valid."
  def errors(content) do
    case JSV.validate(content, @schema) do
      {:ok, _} -> content |> content_errors() |> Enum.uniq()
      {:error, error} -> shape_errors(error)
    end
  end

  @doc "Whether a finished game's ending output is input this story accepts. No output never is."
  def accepts_input?(content, output) do
    root = content["input"] && build(content["input"]["schema"])
    not is_nil(output) and not is_nil(root) and invalid(root, output) == []
  end

  @doc """
  The errors in a series, given each story's slug and head content in order: the first
  story starts without input, and each next one accepts the output of at least one win
  ending of the story before it, and of no loss ending.
  """
  def series_errors([]), do: ["a series needs at least one story"]

  def series_errors([{first, first_content} | _] = stories) do
    slugs = Enum.map(stories, &elem(&1, 0))

    List.flatten([
      for(slug <- duplicates(slugs), do: ~s("#{slug}" is in the series more than once)),
      if(first_content["input"],
        do: [~s(the first story "#{first}" needs input, so it can never start)],
        else: []
      ),
      for {{prev, prev_content}, {next, next_content}} <- Enum.zip(stories, tl(stories)) do
        endings = Enum.with_index(prev_content["endings"] || [], 1)
        unlocks? = fn {ending, _} -> accepts_input?(next_content, ending["output"]) end

        cond do
          is_nil(next_content["input"]) ->
            ~s("#{next}" has no input, so nothing links it to "#{prev}")

          true ->
            [
              if(Enum.any?(endings, &(elem(&1, 0)["outcome"] == "win" and unlocks?.(&1))),
                do: [],
                else: ~s(no win ending of "#{prev}" has output that "#{next}" accepts)
              ),
              for {ending, n} = e <- endings, ending["outcome"] == "loss", unlocks?.(e) do
                ~s(loss ending ##{n} of "#{prev}" has output that "#{next}" accepts)
              end
            ]
        end
      end
    ])
  end

  defp shape_errors(error) do
    for %{instanceLocation: at, errors: errors} <- JSV.normalize_error(error).details,
        # These only summarize the nested errors listed next to them.
        %{kind: kind, message: message} when kind not in [:properties, :boolean_schema] <-
          errors do
      "#{if at == "#", do: "(root)", else: String.trim_leading(at, "#")} #{message}"
    end
  end

  ## The rules

  defp content_errors(v) do
    ids = %{
      locations: MapSet.new(Map.keys(v["locations"])),
      actions: MapSet.new(Map.keys(v["actions"] || %{})),
      items: MapSet.new(all_item_ids(v)),
      supplies: MapSet.new(Map.keys(v["supplies"] || %{})),
      # The context keys a change may root at: those in context.initial or context.schema.
      context:
        MapSet.new(
          Map.keys(v["context"]["initial"] || %{}) ++
            Map.keys(schema_properties(v))
        )
    }

    List.flatten([
      starting_errors(v, ids),
      item_id_errors(v),
      for({id, loc} <- v["locations"], do: location_errors(v, ids, id, loc)),
      for({id, action} <- v["actions"] || %{}, do: action_errors(v, ids, id, action)),
      context_errors(v),
      placeholder_errors(v, ids, v, ""),
      supply_errors(v),
      timeline_errors(v, ids),
      for({rule, i} <- Enum.with_index(v["rules"] || [], 1), do: rule_errors(ids, rule, i)),
      for(
        {ending, i} <- Enum.with_index(v["endings"] || [], 1),
        do: ending_errors(ids, ending, i)
      )
    ])
  end

  defp all_item_ids(v) do
    location_item_ids(v) ++
      Enum.map(v["starting_inventory"] || [], & &1["id"]) ++ Map.keys(v["items"] || %{})
  end

  defp location_item_ids(v),
    do: for({_, loc} <- v["locations"], item <- loc["items"] || [], do: item["id"])

  defp starting_errors(v, ids) do
    start = v["starting_location"]

    if start in ids.locations,
      do: [],
      else: [~s(starting_location "#{start}" is not a defined location)]
  end

  # Item ids are unique across the starting inventory, the rooms and the items catalog, so
  # `isCarrying` always means one item.
  defp item_id_errors(v) do
    starting = Enum.map(v["starting_inventory"] || [], & &1["id"])
    in_rooms = MapSet.new(location_item_ids(v))

    for(id <- duplicates(starting), do: ~s(starting_inventory has duplicate item id "#{id}")) ++
      for(
        id <- Enum.uniq(starting),
        id in in_rooms,
        do: ~s(starting_inventory item id "#{id}" also exists as a location item)
      ) ++
      for(
        id <- Map.keys(v["items"] || %{}),
        id in in_rooms or id in starting,
        do: ~s(items catalog id "#{id}" also exists as a location or starting_inventory item)
      )
  end

  defp location_errors(v, ids, loc_id, loc) do
    where = ~s(location "#{loc_id}")

    [
      for {label, exit} <- loc["exits"] do
        exit_where = ~s(#{where} exit "#{label}")

        [
          if(exit["to"] in ids.locations,
            do: [],
            else: [~s(#{exit_where} points to unknown location "#{exit["to"]}")]
          ),
          gate_errors(
            ids,
            exit_where,
            [exit["visibleWhen"], exit["enabledWhen"]],
            exit["sideEffects"]
          ),
          log_text_errors(exit["sideEffects"], exit_where),
          interrupted_errors(v, exit, exit_where)
        ]
      end,
      gate_errors(ids, "#{where} side effect", [], loc["sideEffects"]),
      log_text_errors(loc["sideEffects"], where),
      for(
        key <- loc["actions"] || [],
        key not in ids.actions,
        do: ~s(#{where} references unknown action "#{key}")
      ),
      for(
        id <- duplicates(Enum.map(loc["items"] || [], & &1["id"])),
        do: ~s(#{where} has duplicate item id "#{id}")
      ),
      for item <- loc["items"] || [] do
        gate_errors(ids, ~s(#{where} item "#{item["id"]}"), [item["availableWhen"]], [])
      end
    ]
  end

  defp action_errors(v, ids, key, action) do
    where = ~s(action "#{key}")

    [
      gate_errors(
        ids,
        where,
        [action["visibleWhen"], action["enabledWhen"]],
        action["sideEffects"]
      ),
      effect_errors(ids, action["effects"] || [], where),
      log_text_errors(action["sideEffects"], where),
      interrupted_errors(v, action, where)
    ]
  end

  # Conditions, and the `when` gates of side effects, may only name real items, supplies
  # and locations.
  defp gate_errors(ids, where, conditions, side_effects) do
    conditions = conditions ++ Enum.map(side_effects || [], & &1["when"])

    [
      for(
        id <- refs(conditions, "isCarrying"),
        id not in ids.items,
        do: ~s(#{where} gates on unknown item id "#{id}")
      ),
      for(
        id <- refs(conditions, "supply"),
        id not in ids.supplies,
        do: ~s(#{where} gates on unknown supply "#{id}")
      ),
      for(
        id <- refs(conditions, "at"),
        id not in ids.locations,
        do: ~s(#{where} gates on unknown location "#{id}")
      )
    ]
  end

  # The values of `key` anywhere in a list of condition trees.
  defp refs(conditions, key) when is_list(conditions),
    do: Enum.flat_map(conditions, &refs(&1, key))

  defp refs(%{"anyOf" => conditions}, key), do: refs(conditions, key)
  defp refs(%{"allOf" => conditions}, key), do: refs(conditions, key)
  defp refs(%{"not" => condition}, key), do: refs(condition, key)
  defp refs(%{} = condition, key) when is_map_key(condition, key), do: [condition[key]]
  defp refs(_condition, _key), do: []

  # A `log` side effect writes its text to the log, so it needs some.
  defp log_text_errors(side_effects, where) do
    for %{"type" => "log"} = effect <- side_effects || [],
        String.trim(effect["text"] || "") == "",
        do: "#{where} has a log side effect with no text"
  end

  # The engine cancels an exit or action when the world changes while its turns pass and
  # its gate stops holding. Then the player must learn why, from its interruptedText.
  defp interrupted_errors(v, choice, where) do
    if interruptible?(v, choice) and String.trim(choice["interruptedText"] || "") == "",
      do: ["#{where} can be interrupted but has no interruptedText"],
      else: []
  end

  # Coarse on purpose: it costs a turn, it has a gate, and something can change while the
  # turns pass (a timeline event or rule with effects, or the clock when the gate reads it).
  defp interruptible?(v, choice) do
    gates = Enum.reject([choice["visibleWhen"], choice["enabledWhen"]], &is_nil/1)

    (choice["timeCost"] || 1) >= 1 and gates != [] and
      (Enum.any?((v["timeline"] || []) ++ (v["rules"] || []), &(&1["effects"] != [])) or
         Enum.any?(~w(turnAtLeast turnAtMost turnEquals), &(refs(gates, &1) != [])))
  end

  # Effects of actions, timeline events and rules: changes go to declared context keys,
  # declared supplies and real items, never to the engine's clock or reserved keys.
  defp effect_errors(ids, effects, where) do
    for effect <- effects do
      case effect do
        %{"give" => id} ->
          if id in ids.items, do: [], else: ~s(#{where} gives unknown item id "#{id}")

        %{"consume" => id} ->
          if id in ids.items, do: [], else: ~s(#{where} consumes unknown item id "#{id}")

        %{"supply" => "turns"} ->
          ~s|#{where} adjusts reserved supply "turns" (the turn clock is not a supply)|

        %{"supply" => id} ->
          if id in ids.supplies, do: [], else: ~s(#{where} adjusts unknown supply "#{id}")

        %{"op" => _, "path" => path} ->
          patch_path_errors(ids, path, where)
      end
    end
  end

  defp patch_path_errors(ids, path, where) do
    case pointer_root(path) do
      "turns" ->
        ~s|#{where} changes reserved path "#{path}" (the turn clock lives outside context)|

      root when is_map_key(@reserved, root) ->
        ~s|#{where} changes reserved path "#{path}" (#{@reserved[root]})|

      root ->
        if root in ids.context,
          do: [],
          else:
            ~s|#{where} changes unknown context path "#{path}" (root key "#{root}" is not declared in context.initial or context.schema)|
    end
  end

  # context.initial must satisfy context.schema, also with each randomize choice, and
  # neither may claim a reserved key. input.schema must be a valid schema.
  defp context_errors(v) do
    initial = v["context"]["initial"] || %{}
    schema = v["context"]["schema"]

    schema_errors =
      cond do
        is_nil(schema) ->
          []

        root = build(schema) ->
          for(message <- invalid(root, initial), do: "context.initial #{message}") ++
            for {key, choices} <- v["context"]["randomize"] || %{},
                is_map_key(initial, key),
                {choice, i} <- Enum.with_index(choices, 1),
                invalid(root, Map.put(initial, key, choice)) != [] do
              ~s(context.randomize "#{key}" choice ##{i} does not satisfy context.schema)
            end

        true ->
          ["context.schema is not a valid JSON Schema"]
      end

    [
      schema_errors,
      for(
        key <- Map.keys(v["context"]["randomize"] || %{}),
        not is_map_key(initial, key),
        do: ~s(context.randomize key "#{key}" is not declared in context.initial)
      ),
      for {key, why} <- @reserved do
        [
          if(is_map_key(initial, key),
            do: [~s|context.initial uses reserved key "#{key}" (#{why})|],
            else: []
          ),
          if(is_map_key(schema_properties(v), key),
            do: [~s|context.schema declares reserved key "#{key}" (#{why})|],
            else: []
          )
        ]
      end,
      if(v["input"] && !build(v["input"]["schema"]),
        do: ["input.schema is not a valid JSON Schema"],
        else: []
      ),
      unknown_keywords("context.schema", schema),
      unknown_keywords("input.schema", v["input"]["schema"])
    ]
  end

  # JSON Schema ignores keywords it doesn't know, so a typo like "requried" would quietly
  # check nothing. A story's own schemas may only use draft-07 keywords.
  @keywords ~w($schema $id $ref $comment title description default examples readOnly
               writeOnly type enum const multipleOf maximum exclusiveMaximum minimum
               exclusiveMinimum maxLength minLength pattern format contentMediaType
               contentEncoding items additionalItems maxItems minItems uniqueItems contains
               maxProperties minProperties required properties patternProperties
               additionalProperties dependencies propertyNames if then else allOf anyOf
               oneOf not definitions)
  # Keywords whose value is a map of schemas, and those whose value is a schema or a list.
  @schema_maps ~w(properties patternProperties definitions dependencies)
  @subschemas ~w(items additionalItems additionalProperties contains propertyNames if then
                 else not allOf anyOf oneOf)

  defp unknown_keywords(where, schema, path \\ "")

  defp unknown_keywords(where, schema, path) when is_map(schema) do
    for {key, value} <- schema do
      cond do
        key not in @keywords ->
          at = if path == "", do: "", else: " at #{path}"
          [~s(#{where}#{at} has unknown keyword "#{key}")]

        key in @schema_maps and is_map(value) ->
          for {name, sub} <- value,
              do: unknown_keywords(where, sub, "#{path}/#{key}/#{name}")

        key in @subschemas and is_list(value) ->
          for {sub, i} <- Enum.with_index(value),
              do: unknown_keywords(where, sub, "#{path}/#{key}/#{i}")

        key in @subschemas ->
          unknown_keywords(where, value, "#{path}/#{key}")

        true ->
          []
      end
    end
  end

  defp unknown_keywords(_where, _schema, _path), do: []

  # A story's own schema, built, or nil when it is not a valid draft-07 JSON Schema.
  defp build(schema) do
    with {:ok, _} <- JSV.validate(schema, @meta_schema),
         {:ok, root} <- JSV.build(schema, default_meta: @draft7) do
      root
    else
      _ -> nil
    end
  rescue
    # JSV raises instead of returning an error for some broken schemas.
    _ -> nil
  end

  defp invalid(root, data) do
    case JSV.validate(data, root) do
      {:ok, _} -> []
      {:error, error} -> shape_errors(error)
    end
  end

  # Placeholders in every string: `{/path}` roots at a declared context key (or the
  # game's input, or `visits` followed by a real location), `{supply:id}` names a declared
  # supply. Labelled by the string's JSON Pointer.
  defp placeholder_errors(v, ids, text, where) when is_binary(text) do
    for [_, ref] <- Regex.scan(@placeholder, text) do
      case ref do
        "supply:" <> id ->
          if id in ids.supplies, do: [], else: ~s(#{where} shows unknown supply "#{id}")

        "/visits/" <> rest ->
          loc = rest |> String.split("/") |> hd()

          if loc in ids.locations,
            do: [],
            else: ~s(#{where} shows visits of unknown location "#{loc}")

        path ->
          root = pointer_root(path)

          if root in ids.context or (root == "input" and v["input"]),
            do: [],
            else: ~s(#{where} shows unknown context path "#{path}")
      end
    end
  end

  defp placeholder_errors(v, ids, map, where) when is_map(map),
    do: for({key, value} <- map, do: placeholder_errors(v, ids, value, "#{where}/#{key}"))

  defp placeholder_errors(v, ids, list, where) when is_list(list) do
    for {value, i} <- Enum.with_index(list),
        do: placeholder_errors(v, ids, value, "#{where}/#{i}")
  end

  defp placeholder_errors(_v, _ids, _value, _where), do: []

  # A supply starts within its own bounds, and its min is not above its max.
  defp supply_errors(v) do
    for {id, d} <- v["supplies"] || %{} do
      min = d["min"] || 0
      max = d["max"]
      initial = d["initial"] || 0

      [
        if(max && min > max,
          do: [~s(supply "#{id}" has min #{min} greater than max #{max})],
          else: []
        ),
        if(initial < min or (max && initial > max),
          do: [
            ~s(supply "#{id}" initial #{initial} is outside its bounds [#{min}, #{max || "∞"}])
          ],
          else: []
        )
      ]
    end
  end

  # Timeline events are strictly ascending by atTurn: the engine runs them in that order.
  defp timeline_errors(v, ids) do
    events = v["timeline"] || []
    turns = Enum.map(events, & &1["atTurn"])

    order =
      for {prev, turn} <- Enum.zip(turns, Enum.drop(turns, 1)) do
        cond do
          turn == prev ->
            "timeline has more than one event at turn #{turn}"

          turn < prev ->
            "timeline is out of order: event at turn #{turn} follows turn #{prev} (events must be sorted ascending by atTurn)"

          true ->
            []
        end
      end

    [
      order,
      for(
        e <- events,
        do: effect_errors(ids, e["effects"], "timeline event at turn #{e["atTurn"]}")
      )
    ]
  end

  defp rule_errors(ids, rule, i) do
    where = "rule ##{i}"

    [
      gate_errors(ids, where, [rule["when"]], rule["sideEffects"]),
      effect_errors(ids, rule["effects"], where),
      log_text_errors(rule["sideEffects"], where)
    ]
  end

  defp ending_errors(ids, ending, i) do
    where = "ending ##{i}"

    [
      gate_errors(ids, where, [ending["when"]], []),
      if(String.trim(ending["message"] || "") == "",
        do: ["#{where} has an empty message"],
        else: []
      )
    ]
  end

  ## Helpers

  # context.schema.properties, when it is an object. Any other value is caught as an invalid
  # schema.
  defp schema_properties(v) do
    case v["context"]["schema"] do
      %{"properties" => %{} = properties} -> properties
      _ -> %{}
    end
  end

  defp duplicates(list),
    do: list |> Enum.frequencies() |> Enum.filter(&(elem(&1, 1) > 1)) |> Enum.map(&elem(&1, 0))

  # The first segment of a JSON Pointer, unescaped.
  defp pointer_root(path) do
    path
    |> String.split("/")
    |> Enum.at(1, "")
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end
end
