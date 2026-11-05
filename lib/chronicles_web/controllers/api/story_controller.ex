defmodule ChroniclesWeb.API.StoryController do
  @moduledoc """
  Stories for tools and scripts. `PUT /api/stories/:slug` with `{"content": {...}}` saves
  content the same way an upload does: a new slug makes a private story, the slug of a
  story you manage gives it a new head version.
  """
  use ChroniclesWeb, :controller

  alias Chronicles.Stories

  action_fallback ChroniclesWeb.API.FallbackController

  def index(conn, _params) do
    render(conn, :index, stories: Stories.list_stories(conn.assigns.current_scope))
  end

  def show(conn, %{"slug" => slug}) do
    with {:ok, story} <- find(conn, slug), do: render(conn, :show, story: story)
  end

  def update(conn, %{"slug" => slug, "content" => %{} = content}) do
    scope = conn.assigns.current_scope

    with {:ok, _story} <- Stories.save_story(scope, slug, content),
         {:ok, story} <- find(conn, slug) do
      render(conn, :show, story: story)
    end
  end

  def update(_conn, _params), do: {:error, :bad_request}

  def delete(conn, %{"slug" => slug}) do
    with {:ok, story} <- find(conn, slug),
         {:ok, _story} <- Stories.delete_story(conn.assigns.current_scope, story) do
      send_resp(conn, :no_content, "")
    end
  end

  defp find(conn, slug) do
    case Stories.find_story(conn.assigns.current_scope, slug) do
      nil -> {:error, :not_found}
      story -> {:ok, story}
    end
  end
end
