defmodule ChroniclesWeb.PageController do
  use ChroniclesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
