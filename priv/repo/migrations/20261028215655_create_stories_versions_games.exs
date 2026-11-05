defmodule Chronicles.Repo.Migrations.CreateStoriesVersionsGames do
  use Ecto.Migration

  def change do
    create table(:stories) do
      add :slug, :string, null: false
      add :visibility, :string, null: false, default: "private"
      add :author_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:stories, [:slug])
    create index(:stories, [:author_id])

    # Immutable snapshots of a story's content (the story JSON).
    create table(:versions) do
      add :story_id, references(:stories, on_delete: :delete_all), null: false
      add :content, :map, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:versions, [:story_id])

    # Set after the first version exists, so it can be empty for a moment.
    alter table(:stories) do
      add :head_version_id, references(:versions, on_delete: :nilify_all)
    end

    # A playthrough of the version it pins. Deleting a story deletes its versions and so
    # its games.
    create table(:games) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :version_id, references(:versions, on_delete: :delete_all), null: false
      add :state, :map, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:games, [:user_id])
    create index(:games, [:version_id])
  end
end
