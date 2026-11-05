defmodule Chronicles.Games.Game do
  @moduledoc """
  A playthrough. It pins the version it was started from, so story edits never break it.
  A game whose state has an ending is final.
  """
  use Ecto.Schema

  schema "games" do
    # Every move replaces the whole state.
    embeds_one :state, Chronicles.Engine.State, on_replace: :delete
    belongs_to :user, Chronicles.Accounts.User
    belongs_to :version, Chronicles.Stories.Version
    # For a story that takes input: the finished game it continues.
    belongs_to :from_game, __MODULE__
    has_many :sequels, __MODULE__, foreign_key: :from_game_id

    timestamps(type: :utc_datetime)
  end
end
