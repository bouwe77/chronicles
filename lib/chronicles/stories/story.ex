defmodule Chronicles.Stories.Story do
  @moduledoc """
  The durable identity of a story that an author owns. Its content lives in versions;
  `head_version` is the current one. `draft` holds the editor's unsaved work, if any.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "stories" do
    field :slug, :string
    field :visibility, Ecto.Enum, values: [:private, :public], default: :private
    field :draft, :map
    belongs_to :author, Chronicles.Accounts.User
    belongs_to :head_version, Chronicles.Stories.Version
    has_many :versions, Chronicles.Stories.Version
    has_one :series_entry, Chronicles.Stories.SeriesEntry

    timestamps(type: :utc_datetime)
  end

  def changeset(story, attrs) do
    story
    |> cast(attrs, [:slug, :visibility])
    |> validate_required([:slug, :visibility])
    |> unique_constraint(:slug)
  end
end
