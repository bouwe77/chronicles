defmodule ChroniclesWeb.API.SeriesController do
  @moduledoc """
  Series for tools and scripts. `PUT /api/series/:slug` with
  `{"title": ..., "stories": [slug, ...]}` creates or replaces a series, after checking
  that it can be played.
  """
  use ChroniclesWeb, :controller

  alias Chronicles.Stories

  action_fallback ChroniclesWeb.API.FallbackController

  def index(conn, _params), do: render(conn, :index, series: Stories.list_series())

  def show(conn, %{"slug" => slug}) do
    with {:ok, series} <- find(slug), do: render(conn, :show, series: series)
  end

  def update(conn, %{"slug" => slug} = params) do
    with {:ok, series} <- Stories.save_series(conn.assigns.current_scope, slug, params) do
      render(conn, :show, series: series)
    end
  end

  def delete(conn, %{"slug" => slug}) do
    with {:ok, series} <- find(slug),
         {:ok, _series} <- Stories.delete_series(conn.assigns.current_scope, series) do
      send_resp(conn, :no_content, "")
    end
  end

  defp find(slug) do
    case Stories.get_series(slug) do
      nil -> {:error, :not_found}
      series -> {:ok, series}
    end
  end
end
