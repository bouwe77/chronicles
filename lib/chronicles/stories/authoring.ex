defmodule Chronicles.Stories.Authoring do
  @moduledoc """
  Pure helpers over a story's content, for the editor: cut out a part to edit as JSON and
  put it back, find where an id is used, and rename, connect or remove locations and
  actions. They only read and change the content; saving is `Chronicles.Stories`.

  A part is `:story` (the top-level fields without their own part), `:context`, `:items`,
  `:supplies`, `:timeline`, `:rules`, `:endings`, `{:location, id}`, `{:action, id}` or
  `:all`. Helpers that can fail return `{:ok, content}` or `{:error, message}`.
  """

  # The top-level fields that are parts of their own, so `:story` leaves them out.
  @own_parts ~w(locations actions context items supplies timeline rules endings)
  @lists [:timeline, :rules, :endings]

  ## Overview

  @doc "The location ids the player can reach from the start by following exits."
  def reachable(content) do
    walk(content["locations"], [content["starting_location"]], MapSet.new())
  end

  defp walk(_locations, [], seen), do: seen

  defp walk(locations, [id | queue], seen) do
    if is_map_key(locations, id) and not MapSet.member?(seen, id) do
      targets = Enum.map(Map.values(locations[id]["exits"] || %{}), & &1["to"])
      walk(locations, queue ++ targets, MapSet.put(seen, id))
    else
      walk(locations, queue, seen)
    end
  end

  @doc """
  Per location, by id: how many exits lead in and out, whether it is the start, and
  whether the player can reach it. An unreachable room is not an error, but usually a
  mistake.
  """
  def summarize(content) do
    live = reachable(content)
    exits = for {_, loc} <- content["locations"], {_, exit} <- loc["exits"] || %{}, do: exit["to"]

    for {id, loc} <- Enum.sort_by(content["locations"], &elem(&1, 0)) do
      %{
        id: id,
        in: Enum.count(exits, &(&1 == id)),
        out: map_size(loc["exits"] || %{}),
        start?: id == content["starting_location"],
        reachable?: id in live
      }
    end
  end

  @doc """
  Every place `needle` is used, as JSON Pointers: a string value equal to it, an object
  key equal to it (marked "(key)"), and for a context path like `/door/locked` also any
  path under it. It walks the raw JSON, so it needs no change when the format grows.
  """
  def uses(content, needle), do: content |> find(needle, "") |> List.flatten()

  defp find(map, needle, at) when is_map(map) do
    for {key, value} <- Enum.sort_by(map, &elem(&1, 0)) do
      path = at <> "/" <> escape(key)
      [if(key == needle, do: [path <> " (key)"], else: []), find(value, needle, path)]
    end
  end

  defp find(list, needle, at) when is_list(list),
    do: for({value, i} <- Enum.with_index(list), do: find(value, needle, "#{at}/#{i}"))

  defp find(value, needle, at) when is_binary(value) do
    if value == needle or
         (String.starts_with?(needle, "/") and String.starts_with?(value, needle <> "/")),
       do: [at],
       else: []
  end

  defp find(_value, _needle, _at), do: []

  defp escape(key), do: key |> String.replace("~", "~0") |> String.replace("/", "~1")

  ## Locations and actions

  @doc """
  Removes a location and every exit that leads to it. Returns the content and the
  removed exits, as `"from → label"`. The starting location can't be removed.
  """
  def remove_location(content, id) do
    cond do
      not is_map_key(content["locations"], id) ->
        {:error, ~s(there is no location "#{id}")}

      id == content["starting_location"] ->
        {:error, ~s("#{id}" is the starting location; choose another start first)}

      true ->
        locations = Map.delete(content["locations"], id)

        removed =
          for {from, loc} <- Enum.sort_by(locations, &elem(&1, 0)),
              {label, exit} <- Enum.sort_by(loc["exits"] || %{}, &elem(&1, 0)),
              exit["to"] == id,
              do: {from, label}

        locations =
          Enum.reduce(removed, locations, fn {from, label}, locations ->
            update_in(locations, [from, "exits"], &Map.delete(&1, label))
          end)

        {:ok, %{content | "locations" => locations},
         Enum.map(removed, fn {from, label} -> "#{from} → #{label}" end)}
    end
  end

  @doc """
  Renames a location id everywhere it is used: its key, `starting_location`, every exit
  `to`, every `at` condition and every item's `descriptionByLocation` key.
  """
  def rename_location(content, from, to) do
    cond do
      not is_map_key(content["locations"], from) -> {:error, ~s(there is no location "#{from}")}
      is_map_key(content["locations"], to) -> {:error, ~s(there is already a location "#{to}")}
      String.trim(to) == "" -> {:error, "a location id can't be empty"}
      true -> {:ok, rename(content, from, to)}
    end
  end

  defp rename(content, from, to) do
    {loc, locations} = Map.pop(content["locations"], from)

    content
    |> Map.put("locations", Map.put(locations, to, loc))
    |> Map.update!("starting_location", &if(&1 == from, do: to, else: &1))
    |> rename_in(from, to)
  end

  # Walks the whole content: exits and `at` conditions can sit anywhere, and so can items.
  defp rename_in(%{"at" => from} = map, from, to) when map_size(map) == 1, do: %{"at" => to}

  defp rename_in(map, from, to) when is_map(map) do
    map
    |> Map.new(fn {key, value} -> {key, rename_in(value, from, to)} end)
    |> rename_exit_target(from, to)
    |> rename_by_location(from, to)
  end

  defp rename_in(list, from, to) when is_list(list), do: Enum.map(list, &rename_in(&1, from, to))
  defp rename_in(value, _from, _to), do: value

  defp rename_exit_target(%{"to" => from} = exit, from, to), do: %{exit | "to" => to}
  defp rename_exit_target(map, _from, _to), do: map

  defp rename_by_location(%{"descriptionByLocation" => %{} = by} = item, from, to)
       when is_map_key(by, from) do
    {text, by} = Map.pop(by, from)
    %{item | "descriptionByLocation" => Map.put(by, to, text)}
  end

  defp rename_by_location(map, _from, _to), do: map

  @doc """
  Adds an exit `label` from `from` to `to`, and an exit `back_label` the other way when
  given. A label the location already has is refused, and then nothing changes.
  """
  def connect(content, from, to, label, back_label \\ nil) do
    with {:ok, content} <- add_exit(content, from, to, label) do
      if back_label in [nil, ""],
        do: {:ok, content},
        else: add_exit(content, to, from, back_label)
    end
  end

  defp add_exit(content, from, to, label) do
    cond do
      not is_map_key(content["locations"], from) ->
        {:error, ~s(there is no location "#{from}")}

      not is_map_key(content["locations"], to) ->
        {:error, ~s(there is no location "#{to}")}

      String.trim(label) == "" ->
        {:error, "an exit label can't be empty"}

      is_map_key(content["locations"][from]["exits"], label) ->
        {:error, ~s("#{from}" already has an exit "#{label}")}

      true ->
        {:ok, put_in(content, ["locations", from, "exits", label], %{"to" => to})}
    end
  end

  @doc "Removes an action, and its key from every location that shows it."
  def remove_action(content, key) do
    if is_map_key(content["actions"] || %{}, key) do
      locations =
        Map.new(content["locations"], fn {id, loc} ->
          {id,
           if(loc["actions"], do: Map.update!(loc, "actions", &List.delete(&1, key)), else: loc)}
        end)

      {:ok,
       %{content | "actions" => Map.delete(content["actions"], key), "locations" => locations}}
    else
      {:error, ~s(there is no action "#{key}")}
    end
  end

  ## Parts

  @doc "A part of the content, or a small template for a location or action that doesn't exist yet."
  def fragment(content, :story), do: Map.drop(content, @own_parts)

  def fragment(content, {:location, id}),
    do: content["locations"][id] || %{"name" => id, "description" => "", "exits" => %{}}

  def fragment(content, {:action, id}),
    do: content["actions"][id] || %{"description" => "", "effects" => []}

  def fragment(content, :context), do: content["context"]
  def fragment(content, :all), do: content
  def fragment(content, part) when part in @lists, do: content[to_string(part)] || []
  def fragment(content, part), do: content[to_string(part)] || %{}

  @doc """
  Puts an edited part back. A part of the wrong JSON type is refused; everything else is
  left to the validator, because work in progress is often invalid. An empty optional
  part (items, supplies, timeline, rules, endings) is left out.
  """
  def put_fragment(content, part, fragment) do
    list? = part in @lists

    cond do
      list? and not is_list(fragment) -> {:error, "#{part} must be a JSON array"}
      not list? and not is_map(fragment) -> {:error, "#{name(part)} must be a JSON object"}
      true -> {:ok, put(content, part, fragment)}
    end
  end

  defp put(content, :story, fragment),
    do: Map.merge(Map.drop(fragment, @own_parts), Map.take(content, @own_parts))

  defp put(content, {:location, id}, fragment), do: put_in(content, ["locations", id], fragment)

  defp put(content, {:action, id}, fragment),
    do: Map.update(content, "actions", %{id => fragment}, &Map.put(&1, id, fragment))

  defp put(content, :context, fragment), do: Map.put(content, "context", fragment)
  defp put(_content, :all, fragment), do: fragment
  defp put(content, part, empty) when empty in [[], %{}], do: Map.delete(content, to_string(part))
  defp put(content, part, fragment), do: Map.put(content, to_string(part), fragment)

  defp name({kind, _id}), do: kind
  defp name(part), do: part
end
