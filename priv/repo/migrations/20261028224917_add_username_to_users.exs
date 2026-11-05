defmodule Chronicles.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :string
    end

    # Existing users get the first part of their email, made unique with their id when
    # two emails share it.
    execute(
      """
      UPDATE users u SET username =
        CASE WHEN (SELECT count(*) FROM users o
                   WHERE lower(split_part(o.email, '@', 1)) = lower(split_part(u.email, '@', 1))) > 1
          THEN split_part(u.email, '@', 1) || u.id
          ELSE split_part(u.email, '@', 1)
        END
      """,
      ""
    )

    alter table(:users) do
      modify :username, :string, null: false, from: {:string, null: true}
    end

    # Unique regardless of case: "Bouwe" and "bouwe" are the same name.
    create unique_index(:users, ["lower(username)"], name: :users_username_index)
  end
end
