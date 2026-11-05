defmodule ChroniclesWeb.API.FallbackController do
  @moduledoc "Turns the `{:error, _}` results of the API controllers into JSON answers."
  use ChroniclesWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      for {field, {message, _}} <- changeset.errors do
        # These messages name what they are about themselves.
        if field in [:content, :stories, :series_entry], do: message, else: "#{field} #{message}"
      end

    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  def call(conn, {:error, :not_found}),
    do: conn |> put_status(:not_found) |> json(%{error: "not found"})

  def call(conn, {:error, :unauthorized}),
    do: conn |> put_status(:forbidden) |> json(%{error: "you may not change this"})

  def call(conn, {:error, :bad_request}),
    do: conn |> put_status(:bad_request) |> json(%{error: ~s(send {"content": {...}})})
end
