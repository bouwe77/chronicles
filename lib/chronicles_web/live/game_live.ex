defmodule ChroniclesWeb.GameLive do
  @moduledoc """
  Plays a game. Every click is one `Chronicles.Games.play/2` call: the engine runs on the
  server, the new state is saved, and the cues of the move go to the `Cues` hook.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.{Engine, Games, Stories}
  alias Chronicles.Engine.LogEntry

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game = Games.get_game!(socket.assigns.current_scope, id)

    socket =
      socket
      |> assign(:page_title, game.version.content["story_title"])
      |> assign_game(game)
      |> stream_configure(:log, dom_id: fn {i, _entry} -> "log-#{i}" end)
      |> stream(:log, Enum.with_index(game.state.log, &{&2, &1}))

    # A new game brings the cues of its starting room in the flash (see `open/3`). A
    # finished game plays its ending cue again whenever it opens.
    cues = Phoenix.Flash.get(socket.assigns.flash, :cues) || []
    cues = if game.state.ending, do: cues ++ [ending_cue(game)], else: cues

    if connected?(socket),
      do: {:ok, socket |> clear_flash(:cues) |> push_cues(cues)},
      else: {:ok, socket}
  end

  @doc """
  Opens a game that was just started. The page changes, so the cues of the starting room
  travel in the flash and play once the game page mounts.
  """
  def open(socket, game, cues) do
    socket
    |> put_flash(:cues, cues)
    |> push_navigate(to: ~p"/games/#{game}")
  end

  @impl true
  def handle_event("go", %{"label" => label}, socket), do: play(socket, {:go, label})
  def handle_event("act", %{"id" => id}, socket), do: play(socket, {:act, id})
  def handle_event("wait", _params, socket), do: play(socket, {:act, :wait})
  def handle_event("take", %{"id" => id}, socket), do: play(socket, {:take, id})
  def handle_event("drop", %{"id" => id}, socket), do: play(socket, {:drop, id})
  def handle_event("notes", %{"notes" => text}, socket), do: play(socket, {:notes, text})

  # A sequel plays again from the same finished game it continued.
  def handle_event("play_again", _params, socket) do
    scope = socket.assigns.current_scope
    game = socket.assigns.game

    started =
      if game.from_game_id,
        do: Games.continue_game(scope, Games.get_game!(scope, game.from_game_id)),
        else: Games.start_game(scope, Stories.get_story!(scope, game.version.story.slug))

    open_new_game(socket, started)
  end

  def handle_event("continue", _params, socket) do
    open_new_game(socket, Games.continue_game(socket.assigns.current_scope, socket.assigns.game))
  end

  defp open_new_game(socket, {:ok, game, cues}), do: {:noreply, open(socket, game, cues)}

  defp open_new_game(socket, {:error, _}),
    do: {:noreply, put_flash(socket, :error, gettext("Could not start a game."))}

  defp play(socket, command) do
    old = socket.assigns.game

    case Games.play(old, command) do
      {:ok, game, cues} ->
        logged = length(old.state.log)
        ended? = game.state.ending && !old.state.ending
        # The log only grows, so an entry's position is its DOM id.
        new_lines = game.state.log |> Enum.drop(logged) |> Enum.with_index(&{&2 + logged, &1})

        {:noreply,
         socket
         |> assign_game(game)
         |> stream(:log, new_lines)
         |> push_cues(if ended?, do: cues ++ [ending_cue(game)], else: cues)}

      {:error, :rejected} ->
        {:noreply, put_flash(socket, :error, gettext("That doesn't work right now."))}

      # The page was out of date (a second tab, a finished game): nothing to do.
      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp assign_game(socket, game) do
    assign(socket,
      game: game,
      view: Engine.view(game.version.content, game.state),
      notes_form: to_form(%{"notes" => game.state.context["notes"] || ""}),
      # The story a finished game continues in, if any.
      sequel: Games.sequel(socket.assigns.current_scope, game)
    )
  end

  # The player's choices read as "> …"; the story's own lines as written.
  defp log_text(%LogEntry{type: :command, text: label}), do: "> " <> label

  defp log_text(%LogEntry{type: :take, text: item}),
    do: "> " <> gettext("take %{item}", item: item)

  defp log_text(%LogEntry{type: :drop, text: item}),
    do: "> " <> gettext("drop %{item}", item: item)

  defp log_text(%LogEntry{type: :wait}), do: "> " <> gettext("Wait")
  defp log_text(%LogEntry{text: text}), do: text

  defp ending_cue(game), do: if(game.state.ending.outcome == :win, do: "confetti", else: "defeat")

  defp push_cues(socket, []), do: socket
  defp push_cues(socket, cues), do: push_event(socket, "cues", %{cues: cues})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div id="game" phx-hook="Cues" class="space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-2">
            <.link
              navigate={~p"/stories/#{@game.version.story.slug}"}
              class="rounded-full p-2 transition hover:bg-base-200"
              aria-label={gettext("Back to the story")}
            >
              <.icon name="hero-chevron-left" class="size-5" />
            </.link>
            <h1 class="text-2xl font-semibold tracking-tight">
              {@game.version.content["story_title"]}
            </h1>
          </div>
          <div class="flex items-center gap-1">
            <button
              :if={@view.notes_enabled?}
              id="notes-toggle"
              type="button"
              phx-click={JS.toggle(to: "#notes-panel")}
              class="rounded-full p-2 transition hover:bg-base-200"
              aria-controls="notes-panel"
              aria-label={gettext("Notes")}
            >
              <.icon name="hero-document-text" class="size-5" />
            </button>
            <button
              id="debug-toggle"
              type="button"
              phx-click={JS.toggle(to: "#debug-panel")}
              class="rounded-full p-2 transition hover:bg-base-200"
              aria-controls="debug-panel"
              aria-label={gettext("Debug")}
            >
              <.icon name="hero-code-bracket" class="size-5" />
            </button>
          </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem]">
          <section
            id="log"
            phx-update="stream"
            phx-hook=".ScrollToEnd"
            aria-label={gettext("Log")}
            class="h-[40vh] space-y-2 overflow-y-auto rounded-2xl border border-base-300 bg-base-100 p-5 lg:h-[75vh]"
          >
            <p
              :for={{id, {_i, entry}} <- @streams.log}
              id={id}
              role={if entry.type == :location, do: "heading"}
              aria-level={if entry.type == :location, do: "3"}
              class={
                case entry.type do
                  :location -> "pt-4 text-lg font-semibold first:pt-0"
                  :outcome -> "leading-relaxed"
                  _choice -> "text-sm italic text-base-content/50"
                end
              }
            >
              {log_text(entry)}
            </p>
          </section>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToEnd">
            export default {
              mounted() {
                const toEnd = () => (this.el.scrollTop = this.el.scrollHeight)
                toEnd()
                new MutationObserver(toEnd).observe(this.el, {childList: true})
              },
            }
          </script>

          <div class="space-y-4">
            <%!-- For authors: which version this game plays, and its context right now. --%>
            <.panel id="debug-panel" class="hidden" title={gettext("Debug")}>
              <h3 class="text-sm font-medium">{gettext("Version")}</h3>
              <p id="debug-version" class="mb-3 font-mono text-sm">
                {@game.version_id}
                <span class="text-base-content/60">
                  ({if @game.version_id == @game.version.story.head_version_id,
                    do: gettext("the latest"),
                    else: gettext("an older version")})
                </span>
              </p>
              <h3 class="text-sm font-medium">{gettext("Context")}</h3>
              <pre
                id="debug-context"
                class="max-h-80 overflow-auto rounded-lg bg-base-200 p-3 font-mono text-xs"
              >{Jason.encode!(@game.state.context, pretty: true)}</pre>
            </.panel>

            <.panel
              :if={@view.notes_enabled?}
              id="notes-panel"
              class="hidden"
              title={gettext("Notes")}
            >
              <.form for={@notes_form} id="notes-form" phx-change="notes">
                <.input
                  field={@notes_form[:notes]}
                  type="textarea"
                  phx-debounce="500"
                  aria-label={gettext("Notes")}
                  placeholder={gettext("Write down what you want to remember.")}
                />
              </.form>
            </.panel>

            <.panel :if={@view.items != []} id="items" title={gettext("Items")}>
              <ul class="space-y-2">
                <li :for={item <- @view.items} class="flex items-center justify-between gap-3">
                  <span>{item["name"]}</span>
                  <.button
                    id={"take-#{item["id"]}"}
                    phx-click="take"
                    phx-value-id={item["id"]}
                    size="sm"
                  >
                    {item["takeLabel"] || gettext("Take")}
                  </.button>
                </li>
              </ul>
            </.panel>

            <.panel :if={@view.actions != []} id="actions" title={gettext("Actions")}>
              <div class="flex flex-wrap gap-2">
                <.button
                  :for={action <- @view.actions}
                  id={"action-#{action.id}"}
                  phx-click={if action.id == :wait, do: "wait", else: "act"}
                  phx-value-id={action.id}
                  disabled={action.disabled?}
                >
                  {if action.id == :wait, do: gettext("Wait"), else: action.label}
                  <.turn_cost :if={@view.uses_time?} n={action.turn_cost} />
                </.button>
              </div>
            </.panel>

            <.panel :if={@view.exits != []} id="exits" title={gettext("Exits")}>
              <div class="flex flex-wrap gap-2">
                <.button
                  :for={{exit, i} <- Enum.with_index(@view.exits)}
                  id={"exit-#{i}"}
                  phx-click="go"
                  phx-value-label={exit.label}
                  disabled={exit.disabled?}
                  class={exit.previous? && "border-dashed"}
                >
                  {exit.label}
                  <.turn_cost :if={@view.uses_time?} n={exit.turn_cost} />
                </.button>
              </div>
            </.panel>

            <.panel :if={@view.uses_time?} id="time" title={gettext("Time")}>
              <span class="text-2xl font-semibold tabular-nums">{@game.state.turns}</span>
            </.panel>

            <.panel :if={@view.supplies != []} id="supplies" title={gettext("You")}>
              <div :for={supply <- @view.supplies} class="flex justify-between">
                <span>{supply.name}</span>
                <span class="font-semibold tabular-nums">{supply.count}</span>
              </div>
            </.panel>

            <.panel id="carrying" title={gettext("Carrying")}>
              <p :if={@view.carrying == []} class="text-sm text-base-content/60">
                {gettext("Nothing yet")}
              </p>
              <ul class="space-y-3">
                <li :for={item <- @view.carrying} class="flex items-start justify-between gap-3">
                  <div>
                    <span class="font-medium">{item["name"]}</span>
                    <p :if={item["description"]} class="text-sm text-base-content/70">
                      {item["description"]}
                    </p>
                  </div>
                  <.button
                    :if={!@game.state.ending}
                    id={"drop-#{item["id"]}"}
                    phx-click="drop"
                    phx-value-id={item["id"]}
                    variant="ghost"
                    size="sm"
                  >
                    {gettext("Drop")}
                  </.button>
                </li>
              </ul>
            </.panel>
          </div>
        </div>
      </div>

      <%!-- Outside #game, so the page shake doesn't move it. --%>
      <div
        :if={@game.state.ending}
        id="ending"
        role="dialog"
        aria-modal="true"
        aria-labelledby="ending-title"
        class="fixed inset-0 z-40 grid place-items-center bg-black/40 p-4 backdrop-blur-sm"
      >
        <div class="w-full max-w-md space-y-4 rounded-2xl bg-base-100 p-6 shadow-xl">
          <h2 id="ending-title" class="text-2xl font-semibold">
            {if @game.state.ending.outcome == :win,
              do: gettext("You won!"),
              else: gettext("You lost")}
          </h2>
          <p class="leading-relaxed">{@game.state.ending.message}</p>
          <div class="flex flex-wrap justify-end gap-2">
            <.button navigate={~p"/stories/#{@game.version.story.slug}"} variant="ghost">
              {gettext("Back to the story")}
            </.button>
            <.button
              id="play-again"
              phx-click="play_again"
              variant={if(@sequel, do: nil, else: "primary")}
            >
              {gettext("Play again")}
            </.button>
            <.button :if={@sequel} id="continue" phx-click="continue" variant="primary">
              {gettext("Continue in %{title}", title: Stories.title(@sequel))}
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <section class={["rounded-2xl border border-base-300 bg-base-100 p-4", @class]} {@rest}>
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-base-content/60">
        {@title}
      </h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :n, :integer, required: true

  defp turn_cost(assigns) do
    ~H"""
    <span :if={@n > 0} class="text-xs opacity-60">
      {ngettext("+%{count} turn", "+%{count} turns", @n)}
    </span>
    """
  end
end
