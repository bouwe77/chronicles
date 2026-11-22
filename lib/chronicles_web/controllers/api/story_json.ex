defmodule ChroniclesWeb.API.StoryJSON do
  alias Chronicles.Stories

  def index(%{stories: stories}), do: %{data: Enum.map(stories, &summary/1)}

  # One story, with its head version's content. After a save, also the problems it causes
  # that didn't stop the save (see `Chronicles.Stories.saga_warnings/1`).
  def show(%{story: story} = assigns) do
    data = %{data: Map.put(summary(story), :content, story.head_version.content)}
    if warnings = assigns[:warnings], do: Map.put(data, :warnings, warnings), else: data
  end

  defp summary(story) do
    %{
      slug: story.slug,
      title: Stories.title(story),
      tags: story.head_version.content["tags"] || [],
      visibility: story.visibility,
      author: story.author.username,
      updated_at: story.updated_at
    }
  end
end
