# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# It is safe to run again: it only adds what is missing.

alias Chronicles.Accounts.User
alias Chronicles.Repo

# An admin for development, who invites other users on /admin/users. The e2e tests log
# in as this admin to invite their test users. Log in with the email; the link is in
# the dev mailbox (/dev/mailbox).
if Mix.env() == :dev and is_nil(Repo.get_by(User, email: "admin@example.com")) do
  %User{role: :admin, confirmed_at: DateTime.utc_now(:second)}
  |> User.admin_changeset(%{email: "admin@example.com", username: "dev-admin", role: :admin})
  |> Repo.insert!()
end
