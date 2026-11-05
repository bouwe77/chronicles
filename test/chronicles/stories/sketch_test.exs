defmodule Chronicles.Stories.SketchTest do
  use ExUnit.Case, async: true

  alias Chronicles.Stories.{Sketch, Validator}

  defp content(title \\ "The Old House", text \\ Sketch.example()),
    do: Sketch.content(title, Sketch.parse(text))

  defp exits(location), do: Map.new(location["exits"], fn {label, e} -> {label, e["to"]} end)

  defp fails(text, error), do: assert(Sketch.parse(text).errors == [error])

  @expected ~s(line 2: expected "- location_id", "  - exit: location_id", "  - item: item_id", "  - action: action_id -> \\"text\\"" or "  - ending: win|loss -> \\"text\\"")

  test "the example is a valid story, starting at its first location" do
    assert Sketch.parse(Sketch.example()).errors == []
    content = content(" The Old House ")
    assert Validator.errors(content) == []
    assert content["story_title"] == "The Old House"
    assert content["starting_location"] == "front_door"
  end

  test "a slug comes from the title" do
    assert Sketch.slug(" The Old Hoüse! ") == "the-old-house"
  end

  test "every exit gets a way back, unless it is one-way, and exits keep their order" do
    locations = content()["locations"]

    assert Map.new(locations, fn {id, loc} -> {id, exits(loc)} end) == %{
             "front_door" => %{"Go inside" => "hall", "Garden" => "garden"},
             "hall" => %{
               "Kitchen" => "kitchen",
               "Bathroom" => "bath_room",
               "Front door" => "front_door"
             },
             "kitchen" => %{"Cellar" => "cellar", "Hall" => "hall"},
             "bath_room" => %{"Hall" => "hall"},
             "cellar" => %{},
             "garden" => %{"Front door" => "front_door"}
           }

    hall = locations["hall"]["exits"]
    assert Enum.map(["Kitchen", "Bathroom", "Front door"], &hall[&1]["order"]) == [1, 2, 3]
  end

  test "names, descriptions, items, actions and log lines" do
    content = content()
    locations = content["locations"]

    assert locations["bath_room"]["name"] == "Bathroom"
    assert locations["front_door"]["description"] == "A heavy oak door, slightly ajar."
    assert locations["hall"]["description"] == ""

    assert locations["hall"]["items"] == [
             %{
               "id" => "umbrella",
               "name" => "Umbrella",
               "description" => "Black, with a broken spoke."
             }
           ]

    assert locations["front_door"]["exits"]["Go inside"]["sideEffects"] ==
             [%{"type" => "log", "text" => "The door creaks open."}]

    refute Map.has_key?(locations["hall"]["exits"]["Front door"], "sideEffects")
    assert locations["hall"]["actions"] == ["ring_bell"]

    assert content["actions"] == %{
             "ring_bell" => %{
               "description" => "Ring the bell",
               "sideEffects" => [%{"type" => "log", "text" => "A bell rings somewhere upstairs."}]
             }
           }

    assert Sketch.parse(~s(- a\n  - action: look -> "Dust."\n)).actions["look"]["description"] ==
             "Look"
  end

  test "an ending under a location ends the game there" do
    assert content()["endings"] == [
             %{
               "when" => %{"at" => "cellar"},
               "outcome" => "win",
               "message" => "You found the cellar."
             }
           ]

    assert Sketch.parse(~s(- a\n  - ending: loss -> "Lost."\n- b\n  - ending: win -> "Won."\n)).endings ==
             [
               %{"when" => %{"at" => "a"}, "outcome" => "loss", "message" => "Lost."},
               %{"when" => %{"at" => "b"}, "outcome" => "win", "message" => "Won."}
             ]

    refute Map.has_key?(content("Open", "- a\n"), "endings")
  end

  test "writing both sides gives one exit each way, and the written label wins" do
    locations = Sketch.parse(~s(- a\n  - exit: b\n- b\n  - exit: a "Back"\n)).locations
    assert exits(locations["a"]) == %{"B" => "b"}
    assert exits(locations["b"]) == %{"Back" => "a"}
  end

  test "mistakes are reported with their line" do
    fails("- a\n  exit b\n", @expected)
    fails("- a\n  - ending: draw -> \"Even.\"\n", @expected)

    fails(
      "  - item: key\n- a\n",
      "line 1: put exits, items, actions and endings under a location"
    )

    fails("- a\n  - ending: win\n", ~s(line 2: the ending at "a" needs a message: -> "text"))

    fails(
      ~s(- a\n  - ending: win -> "Won."\n  - ending: loss -> "Lost."\n),
      ~s(line 3: "a" already has an ending)
    )

    fails("- a\n  - action: look\n", ~s(line 2: action "look" needs a log line: -> "text"))

    fails(
      ~s(- a\n  - action: look -> "Dust."\n- b\n  - action: look -> "Dust."\n),
      ~s(line 4: action "look" is already defined)
    )

    fails("- a\n- a\n", ~s(line 2: location "a" is already defined))
    fails("- a\n  - exit: b\n", ~s(line 2: there is no location "b"))
    fails("- a\n  - exit: a\n", "line 2: an exit cannot lead to its own location")
    fails("- a\n  - item: key\n- b\n  - item: key\n", ~s(line 4: item "key" is already defined))

    fails(
      ~s(- a\n  - exit: b "Go"\n  - exit: c "Go"\n- b\n- c\n),
      ~s(line 3: "a" already has an exit labeled "Go")
    )
  end

  test "an empty sketch gives a story with one empty location" do
    parsed = Sketch.parse("\n")
    assert parsed.errors == []
    blank = Sketch.content("Blank", parsed)
    assert Validator.errors(blank) == []
    assert blank["starting_location"] == "start"
  end
end
