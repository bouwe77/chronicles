defmodule Chronicles.Stories.Sketch do
  @moduledoc """
  Turns a sketch, a short outline of a story, into its first content. One-way: the result
  is a start to continue in the editor; nothing turns content back into a sketch.

      - front_door -> "A heavy oak door, slightly ajar."
        - exit: hall "Go inside" -> "The door creaks open."
        - item: umbrella -> "Black, with a broken spoke."
        - action: ring_bell "Ring the bell" -> "A bell rings somewhere upstairs."
        - ending: win -> "You found the cellar."

  A `- location_id` line starts a location; the lines under it add its exits, items,
  actions and its ending. A `"Name"` after an id overrides the name made from it. `-> "text"`
  is a location's or item's description, an exit's log line, an action's (required) log
  line, or an ending's (required) message: an ending under a location ends the game when
  the player gets there. Every exit also gets a way back, labeled with the location's name,
  unless it is `(one-way)` or the target already leads back. Exits keep the sketch's order.
  """

  @example """
  - front_door -> "A heavy oak door, slightly ajar."
    - exit: hall "Go inside" -> "The door creaks open."
    - exit: garden
  - hall
    - exit: kitchen
    - exit: bath_room
    - item: umbrella -> "Black, with a broken spoke."
    - action: ring_bell "Ring the bell" -> "A bell rings somewhere upstairs."
  - kitchen
    - exit: cellar (one-way)
  - bath_room "Bathroom"
  - cellar
    - ending: win -> "You found the cellar."
  - garden
  """

  @examples %{
    "en" => @example,
    "nl" => """
    - voordeur -> "Een zware eikenhouten deur staat op een kier."
      - exit: hal "Ga naar binnen" -> "De deur gaat krakend open."
      - exit: tuin
    - hal
      - exit: keuken
      - exit: slaap_kamer
      - item: paraplu -> "Zwart, met een gebroken balein."
      - action: luid_bel "Luid de bel" -> "Ergens boven klinkt een bel."
    - keuken
      - exit: kelder (one-way)
    - slaap_kamer "Slaapkamer"
    - kelder
      - ending: win -> "Je hebt de kelder gevonden."
    - tuin
    """
  }

  @expected ~s(expected "- location_id", "  - exit: location_id", "  - item: item_id", "  - action: action_id -> \\"text\\"" or "  - ending: win|loss -> \\"text\\"")

  @doc "The sketch a new story starts with, in the given language (English when there is none). The keywords stay English."
  def example(locale \\ "en"), do: Map.get(@examples, locale, @example)

  @doc ~S'"The Old House" becomes "the-old-house".'
  def slug(title) do
    title
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc "`front_door` becomes `Front door`."
  def name(id), do: id |> String.replace("_", " ") |> String.capitalize()

  @doc """
  Parses a sketch into `%{locations, order, actions, endings, errors}`. `order` lists the
  location ids as written; `errors` are readable lines that start with their line number.
  """
  def parse(text) do
    start = %{
      locations: %{},
      order: [],
      actions: %{},
      endings: [],
      exits: [],
      items: [],
      current: nil,
      problems: []
    }

    parsed =
      text
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(start, &read_line/2)
      |> add_exits()

    errors =
      parsed.problems
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {line, message} -> "line #{line}: #{message}" end)

    %{parsed | order: Enum.reverse(parsed.order), endings: Enum.reverse(parsed.endings)}
    |> Map.take([:locations, :order, :actions, :endings])
    |> Map.put(:errors, errors)
  end

  @doc """
  A story's first content, from its title and a parsed sketch. Without locations it gets
  one empty "start" location, because a story needs a starting location.
  """
  def content(title, %{order: order, locations: locations, actions: actions, endings: endings}) do
    {order, locations} =
      if order == [],
        do: {["start"], %{"start" => %{"name" => "Start", "description" => "", "exits" => %{}}}},
        else: {order, locations}

    %{
      "story_title" => String.trim(title),
      "starting_location" => hd(order),
      "locations" => locations,
      "context" => %{}
    }
    |> put_unless_empty("actions", actions)
    |> put_unless_empty("endings", endings)
  end

  defp put_unless_empty(map, _key, empty) when empty in [%{}, []], do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  ## Lines

  # ` -> "text"`, optional at the end of every line.
  @text ~S'(?: +-> *"([^"]+)")?'

  # Each kind of line, with how many groups its pattern captures.
  defp patterns do
    [
      {:location, ~r/^- ([a-z][a-z0-9_]*)(?: +"([^"]+)")?#{@text} *$/, 3},
      {:exit, ~r/^\s+- exit: *([a-z][a-z0-9_]*)(?: +"([^"]+)")?( +\(one-way\))?#{@text} *$/, 4},
      {:item, ~r/^\s+- item: *([a-z][a-z0-9_]*)(?: +"([^"]+)")?#{@text} *$/, 3},
      {:action, ~r/^\s+- action: *([a-z][a-z0-9_]*)(?: +"([^"]+)")?#{@text} *$/, 3},
      {:ending, ~r/^\s+- ending: *(win|loss)#{@text} *$/, 2}
    ]
  end

  defp read_line({raw, line}, acc) do
    if String.trim(raw) == "", do: acc, else: read_entry(acc, line, entry(raw))
  end

  # `{kind, captures}` for the pattern the line matches, or nil. A group that matched
  # nothing is nil.
  defp entry(raw) do
    Enum.find_value(patterns(), fn {kind, regex, groups} ->
      if captures = Regex.run(regex, raw, capture: :all_but_first) do
        captures = Enum.map(captures, &if(&1 == "", do: nil, else: &1))
        {kind, captures ++ List.duplicate(nil, groups - length(captures))}
      end
    end)
  end

  defp read_entry(acc, line, nil), do: fail(acc, line, @expected)
  defp read_entry(acc, line, {:location, captures}), do: location(acc, line, captures)

  defp read_entry(%{current: nil} = acc, line, _entry),
    do: fail(acc, line, "put exits, items, actions and endings under a location")

  defp read_entry(acc, line, {:exit, [to, label, one_way, text]}) do
    exit = %{
      from: acc.current,
      to: to,
      label: label,
      text: text,
      one_way: one_way != nil,
      line: line
    }

    %{acc | exits: acc.exits ++ [exit]}
  end

  defp read_entry(acc, line, {:item, captures}), do: item(acc, line, captures)
  defp read_entry(acc, line, {:action, captures}), do: action(acc, line, captures)
  defp read_entry(acc, line, {:ending, captures}), do: ending(acc, line, captures)

  defp location(acc, line, [id, name, text]) do
    if Map.has_key?(acc.locations, id) do
      fail(%{acc | current: id}, line, ~s(location "#{id}" is already defined))
    else
      loc = %{"name" => name || name(id), "description" => text || "", "exits" => %{}}
      %{acc | locations: Map.put(acc.locations, id, loc), order: [id | acc.order], current: id}
    end
  end

  defp item(acc, line, [id, name, text]) do
    if id in acc.items do
      fail(acc, line, ~s(item "#{id}" is already defined))
    else
      item = %{"id" => id, "name" => name || name(id)} |> put_text("description", text)

      locations =
        update_in(acc.locations, [acc.current, Access.key("items", [])], &(&1 ++ [item]))

      %{acc | locations: locations, items: [id | acc.items]}
    end
  end

  defp action(acc, line, [id, label, text]) do
    cond do
      is_nil(text) ->
        fail(acc, line, ~s(action "#{id}" needs a log line: -> "text"))

      Map.has_key?(acc.actions, id) ->
        fail(acc, line, ~s(action "#{id}" is already defined))

      true ->
        action = %{"description" => label || name(id), "sideEffects" => log(text)}

        locations =
          update_in(acc.locations, [acc.current, Access.key("actions", [])], &(&1 ++ [id]))

        %{acc | actions: Map.put(acc.actions, id, action), locations: locations}
    end
  end

  defp ending(acc, line, [outcome, text]) do
    cond do
      is_nil(text) ->
        fail(acc, line, ~s(the ending at "#{acc.current}" needs a message: -> "text"))

      Enum.any?(acc.endings, &(&1["when"]["at"] == acc.current)) ->
        fail(acc, line, ~s("#{acc.current}" already has an ending))

      true ->
        ending = %{"when" => %{"at" => acc.current}, "outcome" => outcome, "message" => text}
        %{acc | endings: [ending | acc.endings]}
    end
  end

  ## Exits

  # Each exit as written, then the ways back.
  defp add_exits(acc) do
    {valid, acc} =
      Enum.reduce(acc.exits, {[], acc}, fn exit, {valid, acc} ->
        cond do
          not Map.has_key?(acc.locations, exit.to) ->
            {valid, fail(acc, exit.line, ~s(there is no location "#{exit.to}"))}

          exit.to == exit.from ->
            {valid, fail(acc, exit.line, "an exit cannot lead to its own location")}

          true ->
            {valid ++ [exit], acc}
        end
      end)

    acc =
      Enum.reduce(valid, acc, fn e, acc ->
        add_exit(acc, e.from, e.to, e.label || acc.locations[e.to]["name"], e.line, e.text)
      end)

    Enum.reduce(valid, acc, fn e, acc ->
      leads_back? = Enum.any?(acc.locations[e.to]["exits"], fn {_, x} -> x["to"] == e.from end)

      if e.one_way or leads_back?,
        do: acc,
        else: add_exit(acc, e.to, e.from, acc.locations[e.from]["name"], e.line, nil)
    end)
  end

  defp add_exit(acc, from, to, label, line, text) do
    exits = acc.locations[from]["exits"]

    if Map.has_key?(exits, label) do
      fail(acc, line, ~s("#{from}" already has an exit labeled "#{label}"))
    else
      exit =
        %{"to" => to, "order" => map_size(exits) + 1}
        |> put_text("sideEffects", text && log(text))

      put_in(acc.locations[from]["exits"][label], exit)
    end
  end

  defp log(text), do: [%{"type" => "log", "text" => text}]
  defp put_text(map, _key, nil), do: map
  defp put_text(map, key, value), do: Map.put(map, key, value)

  defp fail(acc, line, message), do: %{acc | problems: acc.problems ++ [{line, message}]}
end
