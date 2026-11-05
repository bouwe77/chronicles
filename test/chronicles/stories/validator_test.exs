defmodule Chronicles.Stories.ValidatorTest do
  use ExUnit.Case, async: true

  alias Chronicles.Stories.Validator

  # A small valid story; each test breaks one thing in it.
  defp story(changes \\ fn v -> v end) do
    changes.(%{
      "story_title" => "Test",
      "starting_location" => "a",
      "context" => %{
        "initial" => %{"door" => "shut"},
        "schema" => %{
          "type" => "object",
          "properties" => %{"door" => %{"enum" => ["shut", "open"]}}
        }
      },
      "locations" => %{
        "a" => %{
          "name" => "A",
          "description" => "Room A.",
          "exits" => %{"east" => %{"to" => "b"}},
          "actions" => ["open"],
          "items" => [%{"id" => "key", "name" => "a key"}]
        },
        "b" => %{"name" => "B", "description" => "Room B.", "exits" => %{}}
      },
      "actions" => %{
        "open" => %{
          "description" => "Open the door",
          "effects" => [%{"op" => "replace", "path" => "/door", "value" => "open"}]
        }
      },
      "supplies" => %{"coin" => %{"name" => "coin", "initial" => 2, "max" => 5}}
    })
  end

  defp errors(changes), do: changes |> story() |> Validator.errors()

  test "a valid story, and the real story fixtures, have no errors" do
    assert Validator.errors(story()) == []

    for id <- ~w(the-number the-number-returns the-bearer-of-this-letter) do
      assert Validator.errors(Chronicles.Play.story(id)) == [], id
    end
  end

  test "the shape comes first: a missing field stops the other checks" do
    assert errors(&Map.delete(&1, "locations")) == ["(root) property 'locations' is required"]
  end

  test "exits, the start and action lists name real things" do
    assert errors(&put_in(&1, ~w(locations a exits east to), "nowhere")) ==
             [~s(location "a" exit "east" points to unknown location "nowhere")]

    assert errors(&Map.put(&1, "starting_location", "nowhere")) ==
             [~s(starting_location "nowhere" is not a defined location)]

    assert errors(&put_in(&1, ~w(locations a actions), ["fly"])) ==
             [~s(location "a" references unknown action "fly")]
  end

  test "conditions name real items, supplies and locations" do
    when_ = %{
      "allOf" => [
        %{"isCarrying" => "lamp"},
        %{"not" => %{"supply" => "gem", "atLeast" => 1}},
        %{"at" => "c"}
      ]
    }

    assert errors(&put_in(&1, ~w(actions open enabledWhen), when_)) == [
             ~s(action "open" gates on unknown item id "lamp"),
             ~s(action "open" gates on unknown supply "gem"),
             ~s(action "open" gates on unknown location "c")
           ]
  end

  test "effects change declared context, never the engine's own keys" do
    effect = fn path ->
      &put_in(&1, ~w(actions open effects), [%{"op" => "replace", "path" => path, "value" => 1}])
    end

    assert [~s(action "open" changes unknown context path "/window") <> _] =
             errors(effect.("/window"))

    assert [~s(action "open" changes reserved path "/turns") <> _] = errors(effect.("/turns"))

    assert [~s(action "open" changes reserved path "/visits/a") <> _] =
             errors(effect.("/visits/a"))
  end

  test "the engine's reserved keys can't be declared" do
    assert [~s(context.initial uses reserved key "notes") <> _ | _] =
             errors(&put_in(&1, ~w(context initial notes), ""))
  end

  test "context.initial satisfies context.schema, and the schema must be valid" do
    assert ["context.initial /door " <> _] = errors(&put_in(&1, ~w(context initial door), "ajar"))

    assert errors(&put_in(&1, ~w(context schema type), "zzz")) == [
             "context.schema is not a valid JSON Schema"
           ]
  end

  test "a story's schemas may only use JSON Schema keywords" do
    assert errors(&put_in(&1, ~w(context schema requried), ["door"])) == [
             ~s(context.schema has unknown keyword "requried")
           ]

    assert errors(&put_in(&1, ~w(context schema properties door maxLenght), 4)) == [
             ~s(context.schema at /properties/door has unknown keyword "maxLenght")
           ]

    # Inside a value, like an enum or a default, any key is fine.
    assert errors(&put_in(&1, ~w(context schema properties door default), %{"x" => 1})) == []
  end

  test "placeholders show something real" do
    assert errors(&put_in(&1, ~w(locations b description), "{/window} {supply:gem} {/visits/c}")) ==
             [
               ~s(/locations/b/description shows unknown context path "/window"),
               ~s(/locations/b/description shows unknown supply "gem"),
               ~s(/locations/b/description shows visits of unknown location "c")
             ]
  end

  test "a supply starts within its bounds" do
    assert errors(&put_in(&1, ~w(supplies coin initial), 9)) ==
             [~s(supply "coin" initial 9 is outside its bounds [0, 5])]
  end

  test "timeline events are in order, one per start turn" do
    event = fn turn -> %{"atTurn" => turn, "effects" => []} end

    assert errors(&Map.put(&1, "timeline", [event.(3), event.(2), event.(2)])) == [
             "timeline is out of order: event at turn 2 follows turn 3 (events must be sorted ascending by atTurn)",
             "timeline has more than one event at turn 2"
           ]
  end

  test "an exit the world can close mid-way needs an interruptedText" do
    timeline = [
      %{"atTurn" => 1, "effects" => [%{"op" => "replace", "path" => "/door", "value" => "open"}]}
    ]

    gated = fn v ->
      v
      |> Map.put("timeline", timeline)
      |> put_in(~w(locations a exits east enabledWhen), %{"path" => "/door", "equals" => "shut"})
    end

    assert errors(gated) == [
             ~s(location "a" exit "east" can be interrupted but has no interruptedText)
           ]

    assert errors(&(gated.(&1) |> put_in(~w(locations a exits east timeCost), 0))) == []
  end

  test "a log side effect and an ending need text" do
    assert errors(&put_in(&1, ~w(locations b sideEffects), [%{"type" => "log", "text" => " "}])) ==
             [~s(location "b" has a log side effect with no text)]

    assert errors(
             &Map.put(&1, "endings", [
               %{"when" => %{"at" => "b"}, "outcome" => "win", "message" => ""}
             ])
           ) ==
             ["ending #1 has an empty message"]
  end
end
