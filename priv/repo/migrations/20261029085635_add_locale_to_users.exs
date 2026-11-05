defmodule Chronicles.Repo.Migrations.AddLocaleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # "en" or "nl"; empty means: the browser's language.
      add :locale, :string
    end
  end
end
