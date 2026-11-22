defmodule ChroniclesWeb.StoryLive do
  @moduledoc """
  One story: start a new game, or open or delete one of your games of it. Those who
  manage the story also make it public or private, or delete it.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.{Games, Stories}
  alias ChroniclesWeb.GameLive

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    story = Stories.get_story!(scope, slug)
    games = Games.list_games(scope, story)

    {:ok,
     socket
     |> assign(page_title: Stories.title(story), story: story)
     |> assign(can_manage?: Stories.can_manage?(scope, story))
     |> assign(chapter: Stories.saga_of(story))
     # Per finished game: the story it continues in, if any.
     |> assign(sequels: sequels(scope, games))
     |> stream(:games, games)}
  end

  defp sequels(scope, games) do
    for game <- games, sequel <- [Games.sequel(scope, game)], sequel, into: %{} do
      {game.id, sequel}
    end
  end

  @impl true
  def handle_event("new_game", _params, socket) do
    case Games.start_game(socket.assigns.current_scope, socket.assigns.story) do
      {:ok, game, cues} -> {:noreply, GameLive.open(socket, game, cues)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not start a game."))}
    end
  end

  def handle_event("continue", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Games.continue_game(scope, Games.get_game!(scope, id)) do
      {:ok, game, cues} -> {:noreply, GameLive.open(socket, game, cues)}
      {:error, _} -> {:noreply, put_flash(socket, :error, gettext("Could not start a game."))}
    end
  end

  def handle_event("delete_game", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    {:ok, game} = Games.delete_game(scope, Games.get_game!(scope, id))
    {:noreply, stream_delete(socket, :games, game)}
  end

  def handle_event("set_visibility", %{"visibility" => visibility}, socket) do
    scope = socket.assigns.current_scope

    case Stories.set_visibility(scope, socket.assigns.story, visibility) do
      {:ok, story} ->
        {:noreply, assign(socket, story: %{socket.assigns.story | visibility: story.visibility})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not change who can see this story."))}
    end
  end

  def handle_event("delete_story", _params, socket) do
    case Stories.delete_story(socket.assigns.current_scope, socket.assigns.story) do
      {:ok, story} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("%{slug} is deleted.", slug: story.slug))
         |> push_navigate(to: ~p"/stories")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("This story is a chapter of a saga. Change or delete the saga first.")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete the story."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={~p"/stories"}
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-chevron-left" class="size-4" /> {gettext("Stories")}
      </.link>
      <div>
        <h1 class="text-3xl font-semibold tracking-tight">{Stories.title(@story)}</h1>
        <p class="text-sm text-base-content/60">
          {gettext("by %{name}", name: @story.author.username)}
        </p>
        <p :if={@chapter} id="saga-chapter" class="text-sm text-base-content/60">
          <.linked_title
            id="saga-link"
            text={
              gettext("Chapter %{n} of %{total} of the saga %{title}",
                n: @chapter.position,
                total: length(@chapter.stories),
                title: "%{title}"
              )
            }
            title={@chapter.saga.title}
            href={~p"/sagas/#{@chapter.saga.slug}"}
          />
        </p>
      </div>
      <p class="text-base-content/80">{@story.head_version.content["description"]}</p>
      <.tags tags={@story.head_version.content["tags"]} />

      <div :if={@can_manage?} id="manage" class="flex flex-wrap items-center gap-2">
        <.button id="edit-story" navigate={~p"/stories/#{@story.slug}/edit"} size="sm">
          <.icon name="hero-pencil-square" class="size-4" /> {gettext("Edit")}
        </.button>
        <%= if @story.visibility == :public do %>
          <.button
            id="make-private"
            phx-click="set_visibility"
            phx-value-visibility="private"
            data-confirm={
              if(@chapter,
                do: gettext("Make the whole saga private? Only you will see its chapters."),
                else: gettext("Make this story private? Only you will see it.")
              )
            }
            size="sm"
          >
            <.icon name="hero-lock-open" class="size-4" /> {gettext("Public")}
          </.button>
        <% else %>
          <.button
            id="make-public"
            phx-click="set_visibility"
            phx-value-visibility="public"
            data-confirm={
              if(@chapter,
                do: gettext("Make the whole saga public? Every user will see its chapters."),
                else: gettext("Make this story public? Every user will see it.")
              )
            }
            size="sm"
          >
            <.icon name="hero-lock-closed" class="size-4" /> {gettext("Private")}
          </.button>
        <% end %>
        <.button
          id="delete-story"
          phx-click="delete_story"
          data-confirm={
            gettext("Delete this story? Every game of it goes too, other players' games as well.")
          }
          variant="ghost"
          size="sm"
        >
          <.icon name="hero-trash" class="size-4" /> {gettext("Delete")}
        </.button>
      </div>

      <%= if @story.head_version.content["input"] do %>
        <p id="needs-input" class="rounded-xl bg-base-200 p-4 text-sm">
          <%= if previous = previous_story(@current_scope, @chapter) do %>
            <.linked_title
              id="previous-story"
              text={
                gettext("This story continues %{title}. Start it from a game of that story you won.",
                  title: "%{title}"
                )
              }
              title={Stories.title(previous)}
              href={~p"/stories/#{previous.slug}"}
            />
          <% else %>
            {if(@chapter,
              do: gettext("This story continues a story before it. Start it from a game you won."),
              else:
                gettext(
                  "This story needs input from a chapter before it, but it is in no saga, so it can't start yet."
                )
            )}
          <% end %>
        </p>
      <% else %>
        <.button id="new-game" phx-click="new_game" variant="primary">
          {gettext("New game")}
        </.button>
      <% end %>

      <h2 class="pt-6 text-lg font-semibold">{gettext("Your games")}</h2>
      <ul id="games" phx-update="stream" class="grid gap-2">
        <li id="games-empty" class="hidden only:block text-sm text-base-content/60">
          {gettext("No games yet.")}
        </li>
        <li :for={{id, game} <- @streams.games} id={id} class="flex flex-wrap items-center gap-2">
          <.link
            navigate={~p"/games/#{game}"}
            class="flex flex-1 items-center justify-between rounded-xl border border-base-300 px-4 py-3 transition hover:border-primary"
          >
            <span class="text-sm">
              {Calendar.strftime(game.updated_at, "%-d %b %Y, %H:%M")}
            </span>
            <span class="text-sm text-base-content/70">{status(game)}</span>
          </.link>
          <.button
            :if={@sequels[game.id]}
            id={"continue-#{game.id}"}
            phx-click="continue"
            phx-value-id={game.id}
            size="sm"
          >
            {gettext("Continue in chapter %{n}: %{title}",
              n: @sequels[game.id].chapter.position,
              title: Stories.title(@sequels[game.id])
            )}
          </.button>
          <.button
            id={"delete-game-#{game.id}"}
            phx-click="delete_game"
            phx-value-id={game.id}
            data-confirm={gettext("Delete this game?")}
            variant="ghost"
            size="sm"
            aria-label={gettext("Delete this game")}
          >
            <.icon name="hero-trash" class="size-4" />
          </.button>
          <%!-- The saga chain: the game this one continues, and the games that continue it. --%>
          <p
            :if={game.from_game_id || game.sequels != []}
            class="w-full space-x-3 px-4 text-xs text-base-content/60"
          >
            <span :if={game.from_game_id}>
              {gettext("continues")}
              <.link navigate={~p"/games/#{game.from_game_id}"} class="underline">
                #{game.from_game_id}
              </.link>
            </span>
            <span :if={game.sequels != []}>
              {gettext("continued in")}
              <.link
                :for={sequel <- game.sequels}
                navigate={~p"/games/#{sequel}"}
                class="underline [&:not(:last-child)]:after:content-[',']"
              >
                #{sequel.id}
              </.link>
            </span>
          </p>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true, doc: "the translated sentence, with %{title} left in"
  attr :title, :string, required: true
  attr :href, :string, required: true

  # A sentence is translated whole, then split at its title, so the title can be a link.
  defp linked_title(assigns) do
    [before, rest] = String.split(assigns.text, "%{title}", parts: 2)
    assigns = assign(assigns, before: before, rest: rest)

    ~H"""
    {@before}<.link
      id={@id}
      navigate={@href}
      class="font-medium underline transition hover:text-primary"
    >{@title}</.link>{@rest}
    """
  end

  # The story before this one in its saga, when the user may see it.
  defp previous_story(scope, %{position: position, stories: stories}) when position > 1 do
    previous = Enum.at(stories, position - 2)
    if Stories.visible?(scope, previous), do: previous
  end

  defp previous_story(_scope, _saga), do: nil

  defp status(game) do
    case game.state.ending do
      %{outcome: :win} -> gettext("Won")
      %{outcome: :loss} -> gettext("Lost")
      nil -> gettext("Playing, turn %{turn}", turn: game.state.turns)
    end
  end
end
