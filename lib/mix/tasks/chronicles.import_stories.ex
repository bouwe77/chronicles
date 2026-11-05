defmodule Mix.Tasks.Chronicles.ImportStories do
  @shortdoc "Imports story JSON files for a user"

  @moduledoc """
  Imports stories from JSON files, each as its first version, for the user with the given
  email. The file name is the story's slug (`the-number.json` becomes `the-number`). Each
  file is a story's content, with an optional `visibility` key (`"private"` or `"public"`,
  default private). A `story_id` key, from older exports, is dropped. A story whose slug
  exists is skipped.

      mix chronicles.import_stories you@example.com ~/stories/*.json
  """
  use Mix.Task

  require Logger

  alias Chronicles.{Accounts, Stories}

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email | files]) when files != [] do
    # Without this, every query is logged in dev.
    Logger.configure(level: :info)
    user = Accounts.get_user_by_email(email) || Mix.raise("No user with email #{email}")

    for file <- files do
      {visibility, content} = file |> File.read!() |> Jason.decode!() |> Map.pop("visibility")
      visibility = if visibility == "public", do: :public, else: :private
      slug = Path.basename(file, ".json")

      case Stories.create_story(user, slug, Map.delete(content, "story_id"), visibility) do
        {:ok, story} -> Mix.shell().info("imported #{story.slug}")
        {:error, error} -> Mix.shell().error("skipped #{file}: #{messages(error)}")
      end
    end
  end

  def run(_), do: Mix.raise("Usage: mix chronicles.import_stories EMAIL FILE...")

  defp messages(changeset),
    do:
      Enum.map_join(changeset.errors, "; ", fn {field, {message, _}} -> "#{field} #{message}" end)
end
