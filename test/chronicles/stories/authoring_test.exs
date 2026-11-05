defmodule Chronicles.Stories.AuthoringTest do
  use ExUnit.Case, async: true

  alias Chronicles.Stories.{Authoring, Validator}

  @story %{
    "story_title" => "Demo",
    "starting_location" => "hall",
    "locations" => %{
      "hall" => %{
        "name" => "Hall",
        "description" => "You are in the hall.",
        "exits" => %{
          "north door" => %{
            "to" => "yard",
            "enabledWhen" => %{"isCarrying" => "key"},
            "interruptedText" => "The door sticks."
          }
        },
        "items" => [%{"id" => "key", "name" => "a key"}],
        "actions" => ["pull"]
      },
      "yard" => %{
        "name" => "Yard",
        "description" => "You are in the yard.",
        "exits" => %{"south" => %{"to" => "hall"}}
      },
      "shed" => %{
        "name" => "Shed",
        "description" => "You are in the shed.",
        "exits" => %{"out" => %{"to" => "yard"}}
      }
    },
    "actions" => %{
      "pull" => %{
        "description" => "Pull",
        "effects" => [%{"op" => "replace", "path" => "/lever/down", "value" => true}]
      }
    },
    "context" => %{"initial" => %{"lever" => %{"down" => false}}}
  }

  test "the story is valid, and an unreachable room is only marked" do
    assert Validator.errors(@story) == []

    assert Authoring.summarize(@story) == [
             %{id: "hall", in: 1, out: 1, start?: true, reachable?: true},
             %{id: "shed", in: 0, out: 1, start?: false, reachable?: false},
             %{id: "yard", in: 2, out: 1, start?: false, reachable?: true}
           ]
  end

  test "find uses: an item id, a context path with a nested use, an action key" do
    assert "/locations/hall/exits/north door/enabledWhen/isCarrying" in Authoring.uses(
             @story,
             "key"
           )

    assert Authoring.uses(@story, "/lever") == ["/actions/pull/effects/0/path"]
    assert Authoring.uses(@story, "pull") == ["/actions/pull (key)", "/locations/hall/actions/0"]
  end

  test "removing a location removes the exits to it; the start stays" do
    assert {:ok, no_shed, []} = Authoring.remove_location(@story, "shed")
    assert Validator.errors(no_shed) == []

    assert {:ok, _, ["hall → north door", "shed → out"]} =
             Authoring.remove_location(@story, "yard")

    assert {:error, ~s("hall" is the starting location) <> _} =
             Authoring.remove_location(@story, "hall")
  end

  test "removing an action takes it out of every location" do
    assert {:ok, content} = Authoring.remove_action(@story, "pull")
    assert content["locations"]["hall"]["actions"] == []
    refute is_map_key(content["actions"], "pull")
  end

  test "renaming a location follows the start, exits, at conditions and descriptionByLocation" do
    story =
      @story
      |> put_in(["locations", "hall", "items"], [
        %{
          "id" => "key",
          "name" => "a key",
          "descriptionByLocation" => %{"hall" => "A key on the floor."}
        }
      ])
      |> Map.put("endings", [
        %{"when" => %{"at" => "hall"}, "outcome" => "win", "message" => "Back."}
      ])

    assert {:ok, renamed} = Authoring.rename_location(story, "hall", "foyer")
    assert Map.keys(renamed["locations"]) |> Enum.sort() == ["foyer", "shed", "yard"]
    assert renamed["starting_location"] == "foyer"
    assert renamed["locations"]["yard"]["exits"]["south"]["to"] == "foyer"

    assert hd(renamed["locations"]["foyer"]["items"])["descriptionByLocation"] == %{
             "foyer" => "A key on the floor."
           }

    assert hd(renamed["endings"])["when"] == %{"at" => "foyer"}
    assert Validator.errors(renamed) == []
    assert Authoring.uses(renamed, "hall") == []

    assert {:error, ~s(there is already a location "yard")} =
             Authoring.rename_location(@story, "hall", "yard")
  end

  test "connecting adds an exit, and one back when a label is given" do
    {:ok, linked} = Authoring.connect(@story, "shed", "hall", "to the hall", "to the shed")
    assert linked["locations"]["shed"]["exits"]["to the hall"] == %{"to" => "hall"}
    assert linked["locations"]["hall"]["exits"]["to the shed"] == %{"to" => "shed"}
    assert Enum.find(Authoring.summarize(linked), &(&1.id == "shed")).reachable?

    {:ok, one_way} = Authoring.connect(@story, "shed", "hall", "in")
    assert Map.keys(one_way["locations"]["hall"]["exits"]) == ["north door"]

    assert {:error, ~s("yard" already has an exit "south")} =
             Authoring.connect(@story, "yard", "hall", "south")

    assert {:error, _} = Authoring.connect(@story, "shed", "yard", "x", "south")
  end

  test "every part round-trips unchanged, and an edit lands in the right place" do
    parts = [
      :story,
      :context,
      :items,
      :supplies,
      :timeline,
      :rules,
      :endings,
      :all,
      {:location, "hall"},
      {:action, "pull"}
    ]

    for part <- parts do
      assert {:ok, @story} ==
               Authoring.put_fragment(@story, part, Authoring.fragment(@story, part)),
             inspect(part)
    end

    {:ok, titled} =
      Authoring.put_fragment(@story, :story, %{"story_title" => "New", "locations" => %{}})

    assert titled["story_title"] == "New"
    assert titled["locations"] == @story["locations"], "the story part can't change other parts"

    assert {:ok, without} =
             Authoring.put_fragment(Map.put(@story, "timeline", [%{}]), :timeline, [])

    refute is_map_key(without, "timeline")

    assert {:error, "endings must be a JSON array"} =
             Authoring.put_fragment(@story, :endings, %{})

    assert {:error, "location must be a JSON object"} =
             Authoring.put_fragment(@story, {:location, "hall"}, [])
  end

  test "a new location or action starts from a template" do
    assert Authoring.fragment(@story, {:location, "attic"}) == %{
             "name" => "attic",
             "description" => "",
             "exits" => %{}
           }

    assert Authoring.fragment(@story, {:action, "jump"}) == %{
             "description" => "",
             "effects" => []
           }
  end
end
