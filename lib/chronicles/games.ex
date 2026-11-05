defmodule Chronicles.Games do
  @moduledoc """
  Games: playthroughs of a story version. Each move runs `Chronicles.Engine` and is saved
  at once. A game whose state has an ending is final.
  """
  import Ecto.Query

  alias Chronicles.Accounts.Scope
  alias Chronicles.Engine
  alias Chronicles.Engine.{Ending, State}
  alias Chronicles.Games.Game
  alias Chronicles.Repo
  alias Chronicles.Stories
  alias Chronicles.Stories.{Story, Validator, Version}

  @doc "The user's games of a story, newest first, with the games that continue them."
  def list_games(%Scope{user: user}, %Story{id: story_id}) do
    from(g in Game,
      join: v in assoc(g, :version),
      where: g.user_id == ^user.id and v.story_id == ^story_id,
      order_by: [desc: g.updated_at, desc: g.id],
      preload: :sequels
    )
    |> Repo.all()
  end

  @doc "One of the user's games, with its version. Raises when there is none."
  def get_game!(%Scope{user: user}, id) do
    Game |> where(id: ^id, user_id: ^user.id) |> preload(version: :story) |> Repo.one!()
  end

  @doc """
  Starts a new game on the story's head version. Returns the game and the cues of the
  starting room. A story that needs input (the next part of a series) can't start on its
  own yet.
  """
  def start_game(%Scope{user: user}, %Story{head_version: version}) do
    if version.content["input"] do
      {:error, :needs_input}
    else
      {state, cues} = Engine.new_game(version.content)

      with {:ok, game} <- Repo.insert(%Game{user: user, version: version, state: state}) do
        {:ok, game, cues}
      end
    end
  end

  @doc """
  The story a finished game continues in: the next story of its series, when the user
  may play it and its input accepts the game's ending output. Nil otherwise.
  """
  def sequel(%Scope{} = scope, %Game{state: %State{ending: %Ending{output: output}}} = game) do
    game = Repo.preload(game, version: :story)
    next = Stories.next_story(scope, game.version.story)

    if next && Validator.accepts_input?(next.head_version.content, output), do: next
  end

  def sequel(_scope, _game), do: nil

  @doc """
  Starts the sequel of one of the user's finished games: a new game of the next story,
  with the game's ending output as its input. Returns the game and the cues of the
  starting room, or `{:error, :no_sequel}`.
  """
  def continue_game(%Scope{user: %{id: user_id} = user} = scope, %Game{user_id: user_id} = from) do
    case sequel(scope, from) do
      nil ->
        {:error, :no_sequel}

      %Story{head_version: version} ->
        {state, cues} = Engine.new_game(version.content, from.state.ending.output)
        game = %Game{user: user, version: version, state: state, from_game_id: from.id}

        with {:ok, game} <- Repo.insert(game), do: {:ok, game, cues}
    end
  end

  def continue_game(_scope, _game), do: {:error, :no_sequel}

  @doc """
  Deletes one of the user's games. Its version goes too when it is no longer its story's
  head and no other game plays it.
  """
  def delete_game(%Scope{user: %{id: user_id}}, %Game{user_id: user_id} = game) do
    Repo.transact(fn ->
      with {:ok, game} <- Repo.delete(game) do
        id = game.version_id

        Repo.delete_all(
          from v in Version,
            where: v.id == ^id,
            where: not exists(from s in Story, where: s.head_version_id == ^id),
            where: not exists(from g in Game, where: g.version_id == ^id)
        )

        {:ok, game}
      end
    end)
  end

  def delete_game(_scope, _game), do: {:error, :unauthorized}

  @doc """
  Plays one `Chronicles.Engine.move/3` command and saves the new state. Returns
  `{:ok, game, cues}` or `{:error, reason}`, and then nothing changed.
  """
  def play(%Game{state: %State{ending: %Ending{}}}, _command), do: {:error, :ended}

  def play(%Game{} = game, command) do
    with {:ok, state, cues} <- Engine.move(game.version.content, game.state, command),
         {:ok, game} <-
           game
           |> Ecto.Changeset.change()
           |> Ecto.Changeset.put_embed(:state, state)
           |> Repo.update() do
      {:ok, game, cues}
    end
  end
end
