defmodule ChroniclesWeb.PageController do
  use ChroniclesWeb, :controller

  # The root opens the stories. A visitor can't see those yet, so they go to log in.
  def home(%{assigns: %{current_scope: %{user: %{}}}} = conn, _params),
    do: redirect(conn, to: ~p"/stories")

  def home(conn, _params), do: redirect(conn, to: ~p"/users/log-in")
end
