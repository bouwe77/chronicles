defmodule Chronicles.Repo.Migrations.RenameSeriesToSagas do
  use Ecto.Migration

  # Series become sagas, and a story's place in one becomes a chapter. Indexes, keys and
  # the sequence keep their old names on a table rename, so they are renamed too: Ecto
  # derives constraint names from the table (`sagas_slug_index`, `chapters_story_id_fkey`).
  def change do
    rename table(:series), to: table(:sagas)
    rename table(:series_stories), to: table(:chapters)
    rename table(:chapters), :series_id, to: :saga_id

    rename_object("SEQUENCE", "series_id_seq", "sagas_id_seq")
    rename_object("INDEX", "series_pkey", "sagas_pkey")
    rename_object("INDEX", "series_slug_index", "sagas_slug_index")
    rename_object("INDEX", "series_author_id_index", "sagas_author_id_index")
    rename_object("INDEX", "series_stories_story_id_index", "chapters_story_id_index")

    rename_object(
      "INDEX",
      "series_stories_series_id_position_index",
      "chapters_saga_id_position_index"
    )

    rename_constraint("sagas", "series_author_id_fkey", "sagas_author_id_fkey")
    rename_constraint("chapters", "series_stories_series_id_fkey", "chapters_saga_id_fkey")
    rename_constraint("chapters", "series_stories_story_id_fkey", "chapters_story_id_fkey")
  end

  defp rename_object(kind, from, to) do
    execute "ALTER #{kind} #{from} RENAME TO #{to}", "ALTER #{kind} #{to} RENAME TO #{from}"
  end

  defp rename_constraint(table, from, to) do
    execute "ALTER TABLE #{table} RENAME CONSTRAINT #{from} TO #{to}",
            "ALTER TABLE #{table} RENAME CONSTRAINT #{to} TO #{from}"
  end
end
