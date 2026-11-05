defmodule ChroniclesWeb.StoryKitControllerTest do
  use ChroniclesWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "the skill zip holds the skill, the format and the schema", %{conn: conn} do
    conn = get(conn, ~p"/story-kit/chronicles-story.zip")

    {:ok, files} = :zip.unzip(response(conn, 200), [:memory])

    assert files |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [
             ~c"chronicles-story/SKILL.md",
             ~c"chronicles-story/story-format.md",
             ~c"chronicles-story/story-schema.json"
           ]

    assert {_, schema} = List.keyfind(files, ~c"chronicles-story/story-schema.json", 0)
    assert %{"type" => "object"} = Jason.decode!(schema)
  end

  test "the format downloads on its own, other names don't", %{conn: conn} do
    assert get(conn, ~p"/story-kit/story-format.md") |> response(200) =~ "Self-check"
    assert get(conn, ~p"/story-kit/SKILL.md") |> response(404)
  end
end
