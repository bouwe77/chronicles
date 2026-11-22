defmodule ChroniclesWeb.API.SagaController do
  @moduledoc """
  Sagas for tools and scripts. `PUT /api/sagas/:slug` with
  `{"title": ..., "stories": [slug, ...]}` creates or replaces a saga, after checking
  that it can be played.
  """
  use ChroniclesWeb, :controller

  alias Chronicles.Stories

  action_fallback ChroniclesWeb.API.FallbackController

  def index(conn, _params), do: render(conn, :index, saga: Stories.list_sagas())

  def show(conn, %{"slug" => slug}) do
    with {:ok, saga} <- find(slug), do: render(conn, :show, saga: saga)
  end

  def update(conn, %{"slug" => slug} = params) do
    with {:ok, saga} <- Stories.save_saga(conn.assigns.current_scope, slug, params) do
      render(conn, :show, saga: saga)
    end
  end

  def delete(conn, %{"slug" => slug}) do
    with {:ok, saga} <- find(slug),
         {:ok, _saga} <- Stories.delete_saga(conn.assigns.current_scope, saga) do
      send_resp(conn, :no_content, "")
    end
  end

  defp find(slug) do
    case Stories.get_saga(slug) do
      nil -> {:error, :not_found}
      saga -> {:ok, saga}
    end
  end
end
