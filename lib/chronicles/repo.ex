defmodule Chronicles.Repo do
  use Ecto.Repo,
    otp_app: :chronicles,
    adapter: Ecto.Adapters.Postgres
end
