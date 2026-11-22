defmodule Chronicles.Stories.Chapter do
  @moduledoc "One story's place in a saga, counted from 1."
  use Ecto.Schema

  @primary_key false
  schema "chapters" do
    belongs_to :saga, Chronicles.Stories.Saga
    belongs_to :story, Chronicles.Stories.Story
    field :position, :integer
  end
end
