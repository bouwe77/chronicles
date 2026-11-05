defmodule Chronicles.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    # Stories in order, where a won game of one unlocks the next.
    create table(:series) do
      add :slug, :string, null: false
      add :title, :string, null: false
      add :author_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:series, [:slug])
    create index(:series, [:author_id])

    create table(:series_stories, primary_key: false) do
      add :series_id, references(:series, on_delete: :delete_all), null: false
      # No cascade: a story a series names can't be deleted.
      add :story_id, references(:stories, on_delete: :nothing), null: false
      add :position, :integer, null: false
    end

    # A story is in at most one series, so its next story is always clear.
    create unique_index(:series_stories, [:story_id])
    create unique_index(:series_stories, [:series_id, :position])

    # The finished game a sequel continues. A sequel keeps its input when that game goes.
    alter table(:games) do
      add :from_game_id, references(:games, on_delete: :nilify_all)
    end
  end
end
