defmodule Chronicles.EngineStoriesTest do
  # Flows through real stories, from test/fixtures/stories.
  use ExUnit.Case, async: true

  import Chronicles.Play

  @opens ~r/She unlocks the steward's door/
  @stands_open ~r/The steward's door stands open, propped/

  defp go(p, labels), do: Enum.reduce(labels, p, &exit(&2, &1))

  defp west(p), do: Enum.find(view(p).exits, &(&1.label == "west"))

  defp wait_until_ending(p),
    do: if(p.state.ending, do: p, else: p |> wait() |> wait_until_ending())

  describe "The Number series: part 1's ending output is part 2's input" do
    setup do
      %{one: story("the-number"), two: story("the-number-returns")}
    end

    test "the fastest win saves three moves", %{one: one} do
      ending = go(start(one), ["add 2", "add 3", "add 2"]).state.ending
      assert ending.outcome == :win
      assert ending.output == %{"spare" => 3}
    end

    test "a win on the last move saves nothing", %{one: one} do
      p = go(start(one), ["add 3", "add 2", "subtract 1", "add 2", "subtract 1", "add 2"])
      assert p.state.ending.output == %{"spare" => 0}
    end

    test "running out of moves is a loss without output", %{one: one} do
      p = go(start(one), ["add 3", "add 2", "add 3", "add 2", "add 3", "add 2"])
      assert p.state.ending.outcome == :loss
      assert p.state.ending.output == nil
    end

    test "part 2 with no spare moves needs the one perfect path", %{two: two} do
      p = go(start(two, input: %{"spare" => 0}), ["subtract 2", "subtract 3", "subtract 2"])
      assert p.state.ending.outcome == :win

      p = go(start(two, input: %{"spare" => 0}), ["subtract 3", "subtract 2", "subtract 3"])
      assert p.state.ending.outcome == :loss
    end

    test "spare moves from part 1 give room for a longer path in part 2", %{two: two} do
      path = ["subtract 3", "subtract 2", "subtract 3", "add 1"]
      p = go(start(two, input: %{"spare" => 0}), Enum.take(path, 3))
      assert p.state.ending.outcome == :loss
      assert go(start(two, input: %{"spare" => 1}), path).state.ending.outcome == :win
    end
  end

  describe "the-bearer-of-this-letter: Agnes and the steward's door" do
    setup do
      v = story("the-bearer-of-this-letter")
      hint = Map.put(v["items"]["ede_hint"], "id", "ede_hint")
      %{v: v, with_ede_hint: &Map.update!(&1, :carrying, fn c -> c ++ [hint] end)}
    end

    test "waiting in the Upper Passage shows Agnes opening the door once", %{v: v} do
      p = v |> start() |> exit("south") |> wait_until(13)
      assert west(p).disabled?
      p = wait_until(p, 16)
      assert count(p, @opens) == 1
      refute west(p).disabled?
    end

    test "arriving on turn 14 shows Agnes, not the open-door entry text", %{v: v} do
      p = v |> start() |> wait_until(13) |> exit("south")
      assert p.state.turns == 14
      assert count(p, @opens) == 1
      assert count(p, @stands_open) == 0
    end

    test "arriving on turn 15 shows the open door, not Agnes", %{v: v} do
      p = v |> start() |> wait_until(14) |> exit("south")
      assert count(p, @opens) == 0
      assert count(p, @stands_open) == 1
    end

    test "the Counting House is safe while Agnes cleans, even mid-search", ctx do
      p =
        ctx.v
        |> start(setup: ctx.with_ede_hint)
        |> exit("south")
        |> wait_until(14)
        |> exit("west")
        |> exit("north")
        |> wait_until(17)

      {p, lines} = during(p, &act(&1, "Search the old rolls"))
      assert p.state.turns == 20
      assert Enum.any?(lines, &(&1 =~ ~r/a bucket clanks on the stair/))
      assert Enum.any?(lines, &(&1 =~ ~r/Nobody cleans Master Osric's counting house/))
      assert Enum.any?(lines, &(&1 =~ ~r/the scrubbing stops/)), "turn 20: you learn she has left"
      assert p.state.context["alarm"]["raised"] == false
      assert Enum.any?(p.state.carrying, &(&1["id"] == "varn_letter"))

      {p, lines} = during(p, &wait/1)
      refute Enum.any?(lines, &(&1 =~ ~r/Agnes/))
      p = p |> exit("south") |> exit("east")
      assert p.state.context["alarm"]["raised"] == false
    end

    test "leaving the Counting House right after the search is safe", ctx do
      p =
        ctx.v
        |> start(setup: ctx.with_ede_hint)
        |> exit("south")
        |> wait_until(14)
        |> exit("west")
        |> exit("north")
        |> wait_until(17)
        |> act("Search the old rolls")

      {p, lines} = during(p, &exit(&1, "south"))
      assert p.state.turns == 21
      refute Enum.any?(lines, &(&1 =~ ~r/Agnes/))
      assert p.state.context["alarm"]["raised"] == false
    end

    test "Agnes catches you in the steward's chamber, and the alarm runs out", %{v: v} do
      p = v |> start() |> exit("south") |> wait_until(14) |> exit("west") |> wait_until(18)
      assert count(p, ~r/a bucket clanks on the stair/) == 1
      p = wait(p)
      assert p.state.context["alarm"]["raised"] == true
      assert count(p, ~r/If you mean to run, run now/) == 1
      p = wait_until_ending(p)
      assert p.state.ending.outcome == :loss
    end

    test "walking in from the Counting House while Agnes cleans gets you caught", %{v: v} do
      p =
        v
        |> start()
        |> exit("south")
        |> wait_until(14)
        |> exit("west")
        |> exit("north")
        |> wait_until(19)
        |> exit("south")

      assert p.state.context["alarm"]["raised"] == true
    end

    test "the steward's door is closed while Agnes cleans", %{v: v} do
      p = v |> start() |> wait_until(18) |> exit("south")
      assert p.state.turns == 19
      assert west(p).disabled?
      assert count(p, ~r/She goes into the steward's room and starts to scrub/) == 1
      p = p |> exit("north") |> exit("south")
      assert count(p, ~r/Inside, Agnes is on her knees/) == 0, "turn 21: she has left"
      refute west(p).disabled?
    end

    test "Agnes locks the door on turn 25, and it stays locked", %{v: v} do
      p = v |> start() |> exit("south") |> wait_until(25)
      assert count(p, ~r/takes her broom and locks the steward's door/) == 1
      assert west(p).disabled?
      p = p |> exit("north") |> exit("south")
      assert count(p, ~r/The steward's door is locked again/) == 1
    end
  end
end
