defmodule Chronicles.Stories.Version do
  @moduledoc """
  An immutable snapshot of a story's content: the story JSON that `Chronicles.Engine` plays.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Chronicles.Stories.Validator

  schema "versions" do
    field :content, :map
    belongs_to :story, Chronicles.Stories.Story

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A changeset for new content. Each `Chronicles.Stories.Validator` error is one error on `:content`."
  def changeset(version, attrs) do
    version
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_change(:content, fn :content, content ->
      for message <- Validator.errors(content), do: {:content, message}
    end)
  end
end
