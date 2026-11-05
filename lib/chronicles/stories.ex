defmodule Chronicles.Stories do
  @moduledoc """
  Stories and their versions. A user sees the public stories and their own; an admin may
  open every story. The author and admins manage a story: its visibility, and deleting it.
  """
  import Ecto.Query

  alias Chronicles.Accounts.{Scope, User}
  alias Chronicles.Games.Game
  alias Chronicles.Repo
  alias Chronicles.Stories.{Series, SeriesEntry, Story, Validator, Version}

  @doc """
  The stories the user may play, with their head version and author. The most recent
  activity comes first: a new version of the story, or the user's last move in a game of
  it.

  Options: `tags:`, only stories that have all of them. `all: true`, for admins, also
  other authors' private stories; without it, an admin's list is an author's list.
  """
  def list_stories(%Scope{user: user} = scope, opts \\ []) do
    from(s in listed(scope, opts[:all]),
      join: v in assoc(s, :head_version),
      as: :head,
      join: a in assoc(s, :author),
      left_join: sv in Version,
      on: sv.story_id == s.id,
      left_join: g in Game,
      on: g.version_id == sv.id and g.user_id == ^user.id,
      group_by: [s.id, v.id, a.id],
      # greatest() skips the null of a story without games.
      order_by: [desc: fragment("greatest(?, max(?))", s.updated_at, g.updated_at), asc: s.slug],
      preload: [head_version: v, author: a]
    )
    |> with_tags(opts[:tags] || [])
    |> Repo.all()
  end

  defp with_tags(query, []), do: query

  # `?&`: the tags array contains all of these strings.
  defp with_tags(query, tags) do
    where(
      query,
      [head: v],
      fragment("?->'tags' \\?& ?", v.content, type(^tags, {:array, :string}))
    )
  end

  @doc "Every tag on the stories `list_stories/2` lists, sorted. Takes its `all:` option."
  def list_tags(%Scope{} = scope, opts \\ []) do
    from(s in listed(scope, opts[:all]),
      join: v in assoc(s, :head_version),
      select: fragment("DISTINCT jsonb_array_elements_text(?->'tags')", v.content)
    )
    |> Repo.all()
    |> Enum.sort()
  end

  @doc "A story the user may play, by slug, with its head version and author. Raises when there is none."
  def get_story!(%Scope{} = scope, slug) do
    scope |> visible() |> where(slug: ^slug) |> preload([:head_version, :author]) |> Repo.one!()
  end

  @doc "Like `get_story!/2`, but nil when there is no such story the user may play."
  def find_story(%Scope{} = scope, slug) do
    scope |> visible() |> where(slug: ^slug) |> preload([:head_version, :author]) |> Repo.one()
  end

  def title(%Story{head_version: %Version{content: content}}), do: content["story_title"]

  @doc "Whether the user manages the story: its author, or an admin."
  def can_manage?(%Scope{user: %User{role: :admin}}, %Story{}), do: true
  def can_manage?(%Scope{user: %User{id: id}}, %Story{author_id: author_id}), do: id == author_id

  @doc """
  Creates a story with `content` as its first version. Invalid content gives
  `{:error, changeset}` with the errors on `:content`, and nothing is saved.
  """
  def create_story(%User{} = author, slug, content, visibility \\ :private) do
    Repo.transact(fn ->
      story = Story.changeset(%Story{author: author}, %{slug: slug, visibility: visibility})

      with {:ok, story} <- Repo.insert(story),
           {:ok, version} <-
             Repo.insert(Version.changeset(%Version{story: story}, %{content: content})) do
        story |> Ecto.Changeset.change(head_version_id: version.id) |> Repo.update()
      end
    end)
  end

  @doc "Whether the user may write stories: authors and admins."
  def can_write?(%Scope{user: %User{role: role}}), do: role in [:author, :admin]

  @doc """
  Saves `content` as a story's new head version: the one way users write stories. A new
  slug creates a private story of the user's own. An existing story must be one they
  manage; its previous head version is deleted when no game plays it. All of it happens
  in one transaction, or nothing does.

  Returns `{:ok, story}`, `{:error, changeset}` for invalid content or slug, or
  `{:error, :unauthorized}`.
  """
  def save_story(%Scope{user: user} = scope, slug, content) do
    if can_write?(scope) do
      case Repo.get_by(Story, slug: slug) do
        nil ->
          create_story(user, slug, content)

        story ->
          if can_manage?(scope, story),
            do: new_version(story, content),
            else: {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Starts a new story with `content` as its first version: like `save_story/3`, but a slug
  that is taken, by any author, is an error and nothing is replaced.
  """
  def start_story(%Scope{user: user} = scope, slug, content) do
    if can_write?(scope), do: create_story(user, slug, content), else: {:error, :unauthorized}
  end

  @doc "Whether any story, of any author, has this slug."
  def slug_taken?(slug), do: Repo.exists?(where(Story, slug: ^slug))

  defp new_version(story, content) do
    Repo.transact(fn ->
      previous = story.head_version_id

      with {:ok, version} <-
             Repo.insert(Version.changeset(%Version{story_id: story.id}, %{content: content})),
           {:ok, story} <-
             story
             |> Ecto.Changeset.change(head_version_id: version.id, draft: nil)
             |> Repo.update() do
        Repo.delete_all(
          from v in Version,
            where: v.id == ^previous,
            where: not exists(from g in Game, where: g.version_id == ^previous)
        )

        {:ok, story}
      end
    end)
  end

  @doc """
  Keeps the editor's unsaved work on the story, or clears it with `nil`. Only for those
  who manage it. A new version clears it too.
  """
  def save_draft(%Scope{} = scope, %Story{} = story, draft) do
    if can_manage?(scope, story),
      do: story |> Ecto.Changeset.change(draft: draft) |> Repo.update(),
      else: {:error, :unauthorized}
  end

  @doc "Makes a story `:public` or `:private`. Only for those who manage it."
  def set_visibility(%Scope{} = scope, %Story{} = story, visibility) do
    if can_manage?(scope, story),
      do: story |> Story.changeset(%{visibility: visibility}) |> Repo.update(),
      else: {:error, :unauthorized}
  end

  @doc """
  Deletes a story with all its versions and every game of them, other players' games
  too. Only for those who manage it.
  """
  def delete_story(%Scope{} = scope, %Story{} = story) do
    if can_manage?(scope, story) do
      story
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.no_assoc_constraint(:series_entry,
        message: "is part of a series; change or delete the series first"
      )
      |> Repo.delete()
    else
      {:error, :unauthorized}
    end
  end

  ## Series

  @doc "Every series, with its stories in order. Every user may read them."
  def list_series do
    Series |> preload([:author, entries: :story]) |> Repo.all()
  end

  def get_series(slug),
    do: Series |> preload([:author, entries: :story]) |> Repo.get_by(slug: slug)

  @doc """
  A story's place in its series, or nil: `%{series, position, stories}`, where `stories`
  are all the series' stories in order, with their head versions. The UI must not show
  stories the user can't see, so it checks `visible?/2`.
  """
  def series_part(%Story{id: id}) do
    entry =
      SeriesEntry
      |> where(story_id: ^id)
      |> preload(series: [entries: [story: :head_version]])
      |> Repo.one()

    entry &&
      %{
        series: entry.series,
        position: entry.position,
        stories: Enum.map(entry.series.entries, & &1.story)
      }
  end

  @doc "Whether the user may see the story: it is public or their own, or they are an admin."
  def visible?(%Scope{user: %User{role: :admin}}, %Story{}), do: true

  def visible?(%Scope{user: user}, %Story{} = story),
    do: story.visibility == :public or story.author_id == user.id

  @doc "The story after this one in its series, when the user may play it, or nil."
  def next_story(%Scope{} = scope, %Story{} = story) do
    with %{position: position, stories: stories} <- series_part(story),
         %Story{} = next <- Enum.at(stories, position),
         true <- visible?(scope, next) do
      next
    else
      _ -> nil
    end
  end

  @doc """
  Creates or replaces a series from `%{"title" => ..., "stories" => [slug, ...]}`. Only
  authors and admins make series; only its author or an admin changes one. Every story
  must be one the user may see, and the series must be playable: see
  `Chronicles.Stories.Validator.series_errors/1`. A story is in at most one series.
  """
  def save_series(%Scope{user: user} = scope, slug, attrs) do
    series = get_series(slug) || %Series{author_id: user.id, entries: []}

    cond do
      not can_write?(scope) ->
        {:error, :unauthorized}

      series.id && not (user.role == :admin or series.author_id == user.id) ->
        {:error, :unauthorized}

      true ->
        do_save_series(scope, series, slug, attrs)
    end
  end

  defp do_save_series(scope, series, slug, attrs) do
    slugs = List.wrap(attrs["stories"])
    stories = Enum.map(slugs, &find_story(scope, &1))
    changeset = Series.changeset(series, %{slug: slug, title: attrs["title"]})

    errors =
      case Enum.find_index(stories, &is_nil/1) do
        nil ->
          in_other_series(series, stories) ++
            Validator.series_errors(Enum.map(stories, &{&1.slug, &1.head_version.content}))

        i ->
          [~s(there is no story "#{Enum.at(slugs, i)}")]
      end

    # add_error puts each error first, so add them in reverse to keep their order.
    changeset =
      errors
      |> Enum.reverse()
      |> Enum.reduce(changeset, &Ecto.Changeset.add_error(&2, :stories, &1))

    Repo.transact(fn ->
      with {:ok, saved} <- Repo.insert_or_update(changeset) do
        Repo.delete_all(where(SeriesEntry, series_id: ^saved.id))

        entries =
          for {story, position} <- Enum.with_index(stories, 1),
              do: %{series_id: saved.id, story_id: story.id, position: position}

        Repo.insert_all(SeriesEntry, entries)
        {:ok, get_series(slug)}
      end
    end)
  end

  # A story is in at most one series.
  defp in_other_series(series, stories) do
    ids = Enum.map(stories, & &1.id)

    for entry <-
          Repo.all(from e in SeriesEntry, where: e.story_id in ^ids, preload: [:story, :series]),
        entry.series_id != series.id,
        do: ~s("#{entry.story.slug}" is already in the series "#{entry.series.slug}")
  end

  @doc "Deletes a series. Its stories stay. Only for its author or an admin."
  def delete_series(%Scope{user: user}, %Series{} = series) do
    if user.role == :admin or series.author_id == user.id,
      do: Repo.delete(series),
      else: {:error, :unauthorized}
  end

  # The stories a user may open and play. Admins manage every story, so they may open it.
  defp visible(%Scope{user: %User{role: :admin}}), do: Story
  defp visible(%Scope{} = scope), do: listed(scope, false)

  # The stories a list shows: an admin's list is an author's list, unless `all`.
  defp listed(%Scope{user: %User{role: :admin}} = scope, true), do: visible(scope)

  defp listed(%Scope{user: user}, _all),
    do: where(Story, [s], s.visibility == :public or s.author_id == ^user.id)
end
