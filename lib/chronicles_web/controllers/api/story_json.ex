defmodule ChroniclesWeb.API.StoryJSON do
  alias Chronicles.Stories

  def index(%{stories: stories}), do: %{data: Enum.map(stories, &summary/1)}

  # One story, with its head version's content.
  def show(%{story: story}),
    do: %{data: Map.put(summary(story), :content, story.head_version.content)}

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
