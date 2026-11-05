defmodule ChroniclesWeb.RateLimitTest do
  use ChroniclesWeb.ConnCase, async: true

  alias ChroniclesWeb.RateLimit

  # A client of its own, so other tests don't count.
  defp request(ip), do: %{build_conn() | remote_ip: ip} |> RateLimit.rate_limit(limit: 2)

  test "the third request in a minute gets 429, other clients don't" do
    ip = {10, 0, 0, 1}
    refute request(ip).halted
    refute request(ip).halted

    conn = request(ip)
    assert conn.halted
    assert json_response(conn, 429)["error"] =~ "too many requests"

    refute request({10, 1, 0, 1}).halted
  end

  test "the API pipeline is limited", %{conn: conn} do
    conn = post(conn, ~p"/api/session", %{})
    refute conn.status == 429
    assert [{{127, 0, 0, 1}, _count}] = :ets.lookup(RateLimit, {127, 0, 0, 1})
  end
end
