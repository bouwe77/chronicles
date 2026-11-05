defmodule Mix.Tasks.Chronicles.PlaythroughTest do
  # Not async: Mix.shell is global.
  use ExUnit.Case, async: false

  @story Path.expand("../../fixtures/stories/the-number.json", __DIR__)

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp run_paths(paths) do
    file = Path.join(System.tmp_dir!(), "paths-#{System.unique_integer([:positive])}.json")
    File.write!(file, Jason.encode!(paths))
    on_exit(fn -> File.rm(file) end)
    Mix.Tasks.Chronicles.Playthrough.run([@story, file])
  end

  test "reports each path's result with the real engine" do
    run_paths(%{
      "win" => %{"steps" => ["go:add 2", "go:add 3", "go:add 2"], "expect" => "win"},
      "broke" => %{"steps" => ["go:add 9"], "expect" => "broke"}
    })

    assert_received {:mix_shell, :info, ["ok    broke: broke at step 1 " <> _]}
    assert_received {:mix_shell, :info, ["ok    win: win at turn 3: " <> _]}
  end

  test "fails when a path ends otherwise than expected" do
    assert_raise Mix.Error, "1 of 1 paths did not end as expected", fn ->
      run_paths(%{"too short" => %{"steps" => ["go:add 2"], "expect" => "win"}})
    end
  end
end
