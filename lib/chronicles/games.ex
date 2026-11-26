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

  @doc "Of these stories, the ids of those the user has won a game of, on any version."
  def won_story_ids(%Scope{user: user}, story_ids) do
    from(g in Game,
      join: v in assoc(g, :version),
      where: g.user_id == ^user.id and v.story_id in ^story_ids,
      where: fragment("?->'ending'->>'outcome' = 'win'", g.state),
      distinct: true,
      select: v.story_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "One of the user's games, with its version. Raises when there is none."
  def get_game!(%Scope{user: user}, id) do
    Game |> where(id: ^id, user_id: ^user.id) |> preload(version: :story) |> Repo.one!()
  end

  @doc """
  Starts a new game on the story's head version. Returns the game and the cues of the
  starting room. A story that needs input (a later chapter of a saga) can't start on its
  own yet.
  """
  def start_game(%Scope{user: user}, %Story{head_version: version} = story) do
    if version.content["input"],
      do: {:error, :needs_input},
      else: insert_new_game(user, story, nil, nil)
  end

  @doc """
  The story a finished game continues in: the next story of its saga, when the user
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

      %Story{} = story ->
        insert_new_game(user, story, from.state.ending.output, from.id)
    end
  end

  def continue_game(_scope, _game), do: {:error, :no_sequel}

  # A game of the story's head version. The story's author gets a game that records its
  # moves and picks, for `reload/2`; nobody else does.
  defp insert_new_game(user, %Story{head_version: version} = story, input, from_game_id) do
    picks = Engine.random_picks(version.content)
    {state, cues} = Engine.new_game(version.content, input, picks)
    state = if story.author_id == user.id, do: %{state | commands: [], picks: picks}, else: state
    game = %Game{user: user, version: version, state: state, from_game_id: from_game_id}

    with {:ok, game} <- Repo.insert(game), do: {:ok, game, cues}
  end

  @doc """
  Moves one of the user's recording games (see `insert_new_game/4`) to its story's head
  version: a new game with the old picks and the old moves replayed, until a move fails.
  The new game keeps the notes and `from_game_id`; the old game is deleted.

  Returns `{:ok, game, result}`, with `result` one of:

  - `:replayed`: every move worked.
  - `{:stopped, replayed, total, command}`: `command` (as stored) failed after
    `replayed` of `total` moves.
  - `{:new_pick, key, value}`: the old pick `value` of `key` is no longer allowed, so the
    game started fresh.
  """
  def reload(
        %Scope{user: %{id: user_id}} = scope,
        %Game{user_id: user_id, state: %State{commands: commands} = old} = game
      )
      when is_list(commands) do
    # Loaded fresh: a preloaded story still points to the old head version.
    %Story{head_version: version} =
      Story |> preload(:head_version) |> Repo.get!(Repo.preload(game, :version).version.story_id)

    content = version.content
    randomize = content["context"]["randomize"] || %{}

    bad_pick =
      Enum.find(randomize, fn {k, values} ->
        Map.has_key?(old.picks, k) and old.picks[k] not in values
      end)

    {picks, commands} =
      if bad_pick,
        do: {Engine.random_picks(content), []},
        else:
          {Map.merge(Engine.random_picks(content), Map.take(old.picks, Map.keys(randomize))),
           commands}

    {state, _cues} = Engine.new_game(content, old.context["input"], picks)
    state = %{state | commands: [], picks: picks}

    {state, failed} =
      Enum.reduce_while(commands, {state, nil}, fn command, {state, nil} ->
        case Engine.move(content, state, decode(command)) do
          {:ok, new, _cues} -> {:cont, {%{new | commands: state.commands ++ [command]}, nil}}
          {:error, _} -> {:halt, {state, command}}
        end
      end)

    state =
      if old.context["notes"],
        do: put_in(state.context["notes"], old.context["notes"]),
        else: state

    new_game = %Game{
      user_id: user_id,
      version: version,
      state: state,
      from_game_id: game.from_game_id
    }

    result =
      cond do
        bad_pick -> {:new_pick, elem(bad_pick, 0), old.picks[elem(bad_pick, 0)]}
        failed -> {:stopped, length(state.commands), length(commands), failed}
        true -> :replayed
      end

    saved =
      Repo.transact(fn ->
        with {:ok, new_game} <- Repo.insert(new_game),
             {:ok, _} <- delete_game(scope, game),
             do: {:ok, new_game}
      end)

    with {:ok, new_game} <- saved, do: {:ok, new_game, result}
  end

  def reload(_scope, _game), do: {:error, :not_recording}

  # A command as a game stores it: a JSON list. The built-in wait is `["wait"]`, so it
  # can't clash with a story action whose id is "wait".
  defp encode({:act, :wait}), do: ["wait"]
  defp encode({kind, id}) when kind in [:go, :act, :take, :drop], do: [Atom.to_string(kind), id]

  defp decode(["wait"]), do: {:act, :wait}
  defp decode(["go", id]), do: {:go, id}
  defp decode(["act", id]), do: {:act, id}
  defp decode(["take", id]), do: {:take, id}
  defp decode(["drop", id]), do: {:drop, id}

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
           |> Ecto.Changeset.put_embed(:state, record(state, command))
           |> Repo.update() do
      {:ok, game, cues}
    end
  end

  # A recording game (`commands` is a list) stores each move. Notes are not a move.
  defp record(%State{commands: nil} = state, _command), do: state
  defp record(state, {:notes, _text}), do: state
  defp record(state, command), do: %{state | commands: state.commands ++ [encode(command)]}
end
