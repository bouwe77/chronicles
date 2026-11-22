defmodule ChroniclesWeb.StoriesLive do
  @moduledoc """
  The stories the user may play, most recent activity first. Tags filter the list; the
  chosen tags live in the URL (`?tags[]=puzzle`), so a filtered list can be shared and the
  back button works. Admins can also list other authors' private stories (`?all=true`).
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Stories

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Stories"))
     |> assign(:can_write?, Stories.can_write?(socket.assigns.current_scope))
     |> assign(:admin?, socket.assigns.current_scope.user.role == :admin)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    tags = params |> Map.get("tags", []) |> List.wrap()
    all? = params["all"] == "true"

    {:noreply,
     socket
     |> assign(tags: tags, all?: all?, all_tags: Stories.list_tags(scope, all: all?))
     |> stream(:stories, with_sagas(Stories.list_stories(scope, tags: tags, all: all?)),
       reset: true
     )}
  end

  # A saga shows as one card, where its most recent chapter would be, with the listed
  # chapters in saga order.
  defp with_sagas(stories) do
    chapters =
      stories |> Enum.filter(& &1.chapter) |> Enum.group_by(& &1.chapter.saga_id)

    stories
    |> Enum.uniq_by(&if(e = &1.chapter, do: {:saga, e.saga_id}, else: &1.id))
    |> Enum.map(fn
      %{chapter: nil} = story ->
        story

      %{chapter: %{saga: saga}} ->
        %{
          id: "saga-#{saga.id}",
          saga: saga,
          chapters: Enum.sort_by(chapters[saga.id], & &1.chapter.position)
        }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-2xl font-semibold tracking-tight">{gettext("Stories")}</h1>
        <div :if={@can_write?} class="flex gap-2">
          <.button id="new-story" navigate={~p"/stories/new"} size="sm">
            <.icon name="hero-plus" class="size-4" /> {gettext("New story")}
          </.button>
          <.button id="upload-story" navigate={~p"/stories/upload"} size="sm">
            <.icon name="hero-arrow-up-tray" class="size-4" /> {gettext("Upload a story")}
          </.button>
          <.button id="new-saga" navigate={~p"/sagas/new"} size="sm">
            <.icon name="hero-queue-list" class="size-4" /> {gettext("New saga")}
          </.button>
        </div>
      </div>

      <nav :if={@admin?} id="list-filter" class="flex gap-2" aria-label={gettext("Which stories")}>
        <.link
          :for={
            {all?, label} <- [{false, gettext("Mine and public")}, {true, gettext("All stories")}]
          }
          id={if all?, do: "show-all", else: "show-mine"}
          patch={~p"/stories?#{query(@tags, all?)}"}
          aria-pressed={to_string(all? == @all?)}
          class={[
            "rounded-lg border px-3 py-1 text-sm transition",
            if(all? == @all?,
              do: "border-primary bg-primary text-primary-content",
              else: "border-base-300 hover:border-primary"
            )
          ]}
        >
          {label}
        </.link>
      </nav>

      <nav
        :if={@all_tags != []}
        id="tag-filter"
        class="flex flex-wrap gap-2"
        aria-label={gettext("Filter by tag")}
      >
        <.link
          :for={tag <- @all_tags}
          patch={~p"/stories?#{query(toggle(@tags, tag), @all?)}"}
          aria-pressed={to_string(tag in @tags)}
          class={[
            "rounded-full border px-3 py-1 text-sm transition",
            if(tag in @tags,
              do: "border-primary bg-primary text-primary-content",
              else: "border-base-300 hover:border-primary"
            )
          ]}
        >
          {tag}
        </.link>
      </nav>

      <ul id="stories" phx-update="stream" class="grid gap-3">
        <li id="stories-empty" class="hidden only:block text-base-content/60">
          {gettext("No stories match.")}
        </li>
        <li :for={{id, item} <- @streams.stories} id={id}>
          <.saga_card :if={is_map_key(item, :saga)} saga={item.saga} chapters={item.chapters} />
          <.story_card :if={!is_map_key(item, :saga)} story={item} />
        </li>
      </ul>
    </Layouts.app>
    """
  end

  attr :saga, :map, required: true
  attr :chapters, :list, required: true

  # The stories of a saga share their visibility, so the lock shows once, on the card.
  defp saga_card(assigns) do
    ~H"""
    <div class="space-y-3 rounded-2xl border border-base-300 bg-base-100 p-4">
      <div class="flex items-start justify-between gap-3">
        <div>
          <.link
            id={"saga-link-#{@saga.id}"}
            navigate={~p"/sagas/#{@saga.slug}"}
            class="font-medium transition hover:text-primary"
          >
            {@saga.title}
          </.link>
          <p class="text-sm text-base-content/60">
            {ngettext(
              "Saga by %{name} · %{count} chapter",
              "Saga by %{name} · %{count} chapters",
              length(@saga.chapters),
              name: @saga.author.username
            )}
          </p>
        </div>
        <.icon
          :if={hd(@chapters).visibility == :private}
          name="hero-lock-closed"
          class="size-4 shrink-0 text-base-content/50"
        />
      </div>
      <ol class="grid gap-1.5">
        <li :for={story <- @chapters}>
          <.link
            id={"saga-chapter-#{story.id}"}
            navigate={~p"/stories/#{story.slug}"}
            class="flex items-center gap-3 rounded-xl border border-base-300 px-3 py-2 text-sm transition hover:translate-x-0.5 hover:border-primary"
          >
            <span class="w-5 text-center tabular-nums text-base-content/50">
              {story.chapter.position}
            </span>
            <span class="flex-1">{Stories.title(story)}</span>
          </.link>
        </li>
      </ol>
    </div>
    """
  end

  attr :story, :map, required: true

  defp story_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/stories/#{@story.slug}"}
      class="block space-y-2 rounded-2xl border border-base-300 bg-base-100 p-4 transition hover:-translate-y-0.5 hover:border-primary hover:shadow-md"
    >
      <div class="flex items-start justify-between gap-3">
        <div>
          <span class="font-medium">{Stories.title(@story)}</span>
          <p class="text-sm text-base-content/60">
            {gettext("by %{name}", name: @story.author.username)}
          </p>
        </div>
        <.icon
          :if={@story.visibility == :private}
          name="hero-lock-closed"
          class="size-4 shrink-0 text-base-content/50"
        />
      </div>
      <p class="text-sm text-base-content/70">{@story.head_version.content["description"]}</p>
      <.tags tags={@story.head_version.content["tags"]} />
    </.link>
    """
  end

  defp query(tags, all?), do: if(all?, do: [tags: tags, all: true], else: [tags: tags])

  defp toggle(tags, tag), do: if(tag in tags, do: List.delete(tags, tag), else: tags ++ [tag])
end
