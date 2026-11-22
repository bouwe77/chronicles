defmodule ChroniclesWeb.SagaLive do
  @moduledoc """
  One saga: its chapters in order, and the user's progress in each. A chapter is won when
  the user won a game of it, ready when it is the first or the one before it is won, and
  locked otherwise. Games start on the chapter pages.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.{Games, Stories}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    saga = Stories.get_visible_saga!(scope, slug)
    won = Games.won_story_ids(scope, Enum.map(saga.chapters, & &1.story_id))

    # Each chapter is ready when the one before it is won; the first always is.
    {chapters, _} =
      Enum.map_reduce(saga.chapters, true, fn chapter, ready? ->
        won? = MapSet.member?(won, chapter.story_id)

        status =
          cond do
            won? -> :won
            ready? -> :ready
            true -> :locked
          end

        {%{
           id: chapter.story_id,
           story: chapter.story,
           position: chapter.position,
           status: status
         }, won?}
      end)

    {:ok,
     socket
     |> assign(page_title: saga.title, saga: saga)
     |> assign(private?: hd(saga.chapters).story.visibility == :private)
     |> stream(:chapters, chapters)}
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
      <div id="saga" class="flex items-start justify-between gap-3">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight">{@saga.title}</h1>
          <p class="text-sm text-base-content/60">
            {ngettext(
              "Saga by %{name} · %{count} chapter",
              "Saga by %{name} · %{count} chapters",
              length(@saga.chapters),
              name: @saga.author.username
            )}
          </p>
        </div>
        <.icon :if={@private?} name="hero-lock-closed" class="mt-2 size-5 text-base-content/50" />
      </div>

      <ol id="chapters" phx-update="stream" class="grid gap-3">
        <li :for={{id, chapter} <- @streams.chapters} id={id}>
          <.link
            navigate={~p"/stories/#{chapter.story.slug}"}
            data-status={chapter.status}
            class={[
              "flex items-start gap-4 rounded-2xl border border-base-300 bg-base-100 p-4 transition hover:-translate-y-0.5 hover:border-primary hover:shadow-md",
              chapter.status == :locked && "opacity-60"
            ]}
          >
            <span class="pt-0.5 text-2xl font-semibold tabular-nums text-base-content/40">
              {chapter.position}
            </span>
            <div class="flex-1 space-y-1">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="font-medium">{Stories.title(chapter.story)}</span>
                <.status status={chapter.status} />
              </div>
              <p class="text-sm text-base-content/70">
                {chapter.story.head_version.content["description"]}
              </p>
            </div>
          </.link>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp status(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium",
      case @status do
        :won -> "bg-success/15 text-success"
        :ready -> "bg-primary/15 text-primary"
        :locked -> "bg-base-200 text-base-content/60"
      end
    ]}>
      <%= case @status do %>
        <% :won -> %>
          <.icon name="hero-check-mini" class="size-3.5" /> {gettext("Won")}
        <% :ready -> %>
          <.icon name="hero-play-mini" class="size-3.5" /> {gettext("Ready to play")}
        <% :locked -> %>
          {gettext("Locked")}
      <% end %>
    </span>
    """
  end
end
