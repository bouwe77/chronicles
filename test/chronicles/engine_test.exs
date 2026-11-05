defmodule Chronicles.EngineTest do
  # Engine behaviour on tiny inline versions, independent of any authored story.
  use ExUnit.Case, async: true

  import Chronicles.Play

  defp version(extra \\ %{}) do
    Map.merge(
      %{
        "story_id" => "test",
        "story_title" => "Test",
        "starting_location" => "a",
        "items" => %{},
        "locations" => %{
          "a" => %{
            "name" => "A",
            "description" => "You are in A.",
            "exits" => %{"east" => %{"to" => "b"}},
            "actions" => ["think"]
          },
          "b" => %{
            "name" => "B",
            "description" => "You are in B.",
            "sideEffects" => [
              %{"type" => "log", "text" => "B at turn 2.", "when" => %{"turnEquals" => 2}}
            ],
            "exits" => %{"west" => %{"to" => "a"}}
          }
        },
        "actions" => %{"think" => %{"description" => "Think", "timeCost" => 3}}
      },
      extra
    )
  end

  test "a turnEquals rule fires once, also inside a multi-turn action" do
    rules = [
      %{
        "when" => %{"allOf" => [%{"at" => "a"}, %{"turnEquals" => 2}]},
        "effects" => [],
        "sideEffects" => [%{"type" => "log", "text" => "Tick."}]
      }
    ]

    p = version(%{"rules" => rules}) |> start() |> act("Think")
    assert p.state.turns == 3
    assert count(p, ~r/^Tick\.$/) == 1
  end

  test "on-entry side effects read the arrival turn" do
    p = version() |> start() |> act("Think")
    assert count(p, ~r/^B at turn 2\.$/) == 0

    q = version() |> start() |> exit("east") |> exit("west") |> exit("east")
    assert q.state.turns == 3
    assert count(q, ~r/^B at turn 2\.$/) == 0

    r = version(%{"waitEnabled" => true}) |> start() |> wait() |> exit("east")
    assert r.state.turns == 2
    assert count(r, ~r/^B at turn 2\.$/) == 1
  end

  test "a game reads its input at /input, and an ending carries its output" do
    v =
      version(%{
        "input" => %{"schema" => %{"type" => "object"}},
        "endings" => [
          %{
            "when" => %{"allOf" => [%{"at" => "b"}, %{"path" => "/input/key", "equals" => true}]},
            "outcome" => "win",
            "message" => "Out.",
            "output" => %{"out" => true}
          }
        ]
      })

    assert (v |> start(input: %{"key" => false}) |> exit("east")).state.ending == nil

    assert (v |> start(input: %{"key" => true}) |> exit("east")).state.ending.output ==
             %{"out" => true}
  end

  test "an exit the world closes mid-way logs its interruptedText and stays put" do
    v =
      version(%{
        "context" => %{"initial" => %{"bridge" => "down"}},
        "timeline" => [
          %{
            "atTurn" => 1,
            "effects" => [%{"op" => "replace", "path" => "/bridge", "value" => "up"}]
          }
        ]
      })
      |> put_in(["locations", "a", "exits", "east"], %{
        "to" => "b",
        "enabledWhen" => %{"path" => "/bridge", "equals" => "down"},
        "interruptedText" => "The bridge is {/bridge}."
      })

    p = v |> start() |> exit("east")
    assert p.state.turns == 1
    assert count(p, ~r/^You are in B\.$/) == 0
    assert count(p, ~r/^The bridge is up\.$/) == 1
  end
end
