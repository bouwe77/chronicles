defmodule Chronicles.Engine.LogEntry do
  @moduledoc """
  One line of a game's log. The player's choices are `:command` (text: the exit or action
  label), `:take` and `:drop` (text: the item name) and `:wait`. The story's own lines are
  `:location` (a room name) and `:outcome`. How a choice reads, and in which language, is
  up to the UI.
  """
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :turn, :integer
    field :type, Ecto.Enum, values: [:command, :take, :drop, :wait, :location, :outcome]
    field :text, :string
  end
end
