defmodule Mix.Tasks.Chronicles.SetRole do
  @shortdoc "Sets a user's role (player, author or admin)"

  @moduledoc """
  Sets a user's role. Use it to make the first admin; after that, admins change roles in
  the app.

      mix chronicles.set_role you@example.com admin
  """
  use Mix.Task

  require Logger

  alias Chronicles.Accounts
  alias Chronicles.Accounts.User
  alias Chronicles.Repo

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email, role]) when role in ~w(player author admin) do
    # Without this, every query is logged in dev.
    Logger.configure(level: :info)
    user = Accounts.get_user_by_email(email) || Mix.raise("No user with email #{email}")
    user |> User.role_changeset(%{role: role}) |> Repo.update!()
    Mix.shell().info("#{email} is now #{role}")
  end

  def run(_), do: Mix.raise("Usage: mix chronicles.set_role EMAIL player|author|admin")
end
