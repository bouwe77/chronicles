defmodule Chronicles.Engine.Ending do
  @moduledoc """
  How a game ended, on which turn. `output` is what the ending hands on to the next story
  of a series.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :outcome, Ecto.Enum, values: [:win, :loss]
    field :message, :string
    field :turn, :integer
    field :output, :map
  end
end
