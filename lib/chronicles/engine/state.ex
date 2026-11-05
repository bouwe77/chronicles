defmodule Chronicles.Engine.State do
  @moduledoc """
  A game's state: where the player is, what they carry, the clock, the log and the ending.
  A game stores it in one `jsonb` column. The parts a story defines (its context values,
  items and supplies) are maps with the story's own string keys.
  """
  use Ecto.Schema

  alias Chronicles.Engine.{Ending, LogEntry}

  @primary_key false
  embedded_schema do
    field :location, :string
    field :previous_location, :string
    # The story's own values, plus the reserved "visits", "notes" and "input".
    field :context, :map, default: %{}
    # Item maps, oldest first.
    field :carrying, {:array, :map}, default: []
    # Location id => item maps. Locations without items are left out.
    field :location_items, :map, default: %{}
    # Supply id => amount.
    field :supplies, :map, default: %{}
    field :turns, :integer, default: 0
    embeds_many :log, LogEntry
    # Nil while the game is live.
    embeds_one :ending, Ending
  end
end
