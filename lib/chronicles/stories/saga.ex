defmodule Chronicles.Stories.Saga do
  @moduledoc """
  Stories in order, where a won game of one story unlocks the next. The stories carry the
  link themselves (an ending's `output`, the next story's `input`); the saga only names
  them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "sagas" do
    field :slug, :string
    field :title, :string
    belongs_to :author, Chronicles.Accounts.User
    has_many :chapters, Chronicles.Stories.Chapter, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(saga, attrs) do
    saga
    |> cast(attrs, [:slug, :title])
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
  end
end
