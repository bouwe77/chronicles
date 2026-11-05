defmodule Chronicles.Repo.Migrations.AddDraftToStories do
  use Ecto.Migration

  def change do
    alter table(:stories) do
      # The editor's unsaved work, if any. A save or upload clears it.
      add :draft, :map
    end
  end
end
