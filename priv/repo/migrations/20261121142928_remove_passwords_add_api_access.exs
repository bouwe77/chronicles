defmodule Chronicles.Repo.Migrations.RemovePasswordsAddApiAccess do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Login is by email link only.
      remove :hashed_password, :string
      # Whether the user may use the JSON API. Only an admin turns it on.
      add :api_access, :boolean, null: false, default: false
    end
  end
end
