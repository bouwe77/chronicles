defmodule Chronicles.Repo.Migrations.ExitIdsAndNames do
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  # Exits were keyed by their label; now the key is an id and the label is `name`. Actions
  # move from `description` to `name`. Changes every version's content and every draft.
  # Self-contained on purpose: the app's code may change after this migration.
  def up do
    for {id, content} <- repo().all(from(v in "versions", select: {v.id, v.content})) do
      repo().update_all(from(v in "versions", where: v.id == ^id),
        set: [content: convert_content(content)]
      )
    end

    for {id, draft} <-
          repo().all(from(s in "stories", where: not is_nil(s.draft), select: {s.id, s.draft})) do
      repo().update_all(from(s in "stories", where: s.id == ^id),
        set: [draft: convert_content(draft)]
      )
    end
  end

  def down, do: raise(Ecto.MigrationError, "exit ids can't be turned back into labels")

  defp convert_content(%{} = content) do
    content
    |> update_map(
      "locations",
      &Map.new(&1, fn {id, loc} ->
        {id, update_map(loc, "exits", fn exits -> convert_exits(exits) end)}
      end)
    )
    |> update_map(
      "actions",
      &Map.new(&1, fn {id, action} -> {id, convert_action(id, action)} end)
    )
  end

  defp convert_content(other), do: other

  defp update_map(map, key, fun) do
    case map do
      %{^key => %{} = value} -> Map.put(map, key, fun.(value))
      _ -> map
    end
  end

  # Sorted, so a clash between ids gets its suffix the same way each time.
  defp convert_exits(exits) do
    exits
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {label, exit}, acc ->
      id = unique(id(label), acc, 1)
      Map.put(acc, id, Map.put(exit, "name", label))
    end)
  end

  defp unique(id, taken, n) do
    candidate = if n == 1, do: id, else: "#{id}_#{n}"
    if is_map_key(taken, candidate), do: unique(id, taken, n + 1), else: candidate
  end

  defp id(label) do
    id =
      label
      |> String.downcase()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    if id == "", do: "exit", else: id
  end

  defp convert_action(id, %{} = action) do
    {description, action} = Map.pop(action, "description")

    name =
      if description in [nil, ""],
        do: id |> String.replace("_", " ") |> String.capitalize(),
        else: description

    Map.put(action, "name", name)
  end

  defp convert_action(_id, action), do: action
end
