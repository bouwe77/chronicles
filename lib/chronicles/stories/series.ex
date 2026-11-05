defmodule Chronicles.Stories.Series do
  @moduledoc """
  Stories in order, where a won game of one story unlocks the next. The stories carry the
  link themselves (an ending's `output`, the next story's `input`); the series only names
  them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "series" do
    field :slug, :string
    field :title, :string
    belongs_to :author, Chronicles.Accounts.User
    has_many :entries, Chronicles.Stories.SeriesEntry, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(series, attrs) do
    series
    |> cast(attrs, [:slug, :title])
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
  end
end
