defmodule ChroniclesWeb.RateLimit do
  @moduledoc """
  At most `:api_rate_limit` requests (default 100) per client IP per minute, for the JSON
  API. More answers 429.

  The plug counts in an ETS table; this process owns the table and empties it every
  minute, so each minute is a fresh window. On Fly the client IP is in `Fly-Client-IP`,
  which Fly sets and a client can't fake. Anywhere else that header isn't trusted, and
  the socket address is the client.
  """
  use GenServer
  import Plug.Conn

  # ponytail: in-memory window per machine; a shared store if the app runs on several.
  @table __MODULE__
  @window :timer.minutes(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, write_concurrency: true])
    :timer.send_interval(@window, :reset)
    {:ok, nil}
  end

  @impl true
  def handle_info(:reset, state) do
    :ets.delete_all_objects(@table)
    {:noreply, state}
  end

  @doc "The plug. `limit:` overrides the configured limit."
  def rate_limit(conn, opts) do
    limit = opts[:limit] || Application.get_env(:chronicles, :api_rate_limit, 100)

    if :ets.update_counter(@table, client(conn), 1, {nil, 0}) > limit do
      conn
      |> put_status(:too_many_requests)
      |> Phoenix.Controller.json(%{error: "too many requests, try again in a minute"})
      |> halt()
    else
      conn
    end
  end

  defp client(conn) do
    with true <- System.get_env("FLY_APP_NAME") != nil,
         [ip | _] <- get_req_header(conn, "fly-client-ip") do
      ip
    else
      _ -> conn.remote_ip
    end
  end
end
