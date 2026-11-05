defmodule ChroniclesWeb.NewStoryLive do
  @moduledoc """
  Start a story from a title and a sketch: an outline of locations, exits, items, actions
  and endings (see `Chronicles.Stories.Sketch`), checked while you type. Creating it saves
  the first version.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Stories
  alias Chronicles.Stories.{Sketch, Validator}

  @impl true
  def mount(_params, _session, socket) do
    if Stories.can_write?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(:page_title, gettext("New story"))
       |> check(%{
         "title" => "",
         "sketch" => Sketch.example(Gettext.get_locale(ChroniclesWeb.Gettext))
       })}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Only authors can write stories."))
       |> push_navigate(to: ~p"/stories")}
    end
  end

  @impl true
  def handle_event("check", %{"story" => params}, socket), do: {:noreply, check(socket, params)}

  def handle_event("create", %{"story" => params}, socket) do
    socket = check(socket, params)
    %{slug: slug, content: content, errors: errors, taken?: taken?} = socket.assigns

    if errors == [] and slug != "" and not taken? do
      case Stories.start_story(socket.assigns.current_scope, slug, content) do
        {:ok, story} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("%{title} is created.", title: content["story_title"]))
           |> push_navigate(to: ~p"/stories/#{story.slug}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not create the story."))}
      end
    else
      {:noreply, socket}
    end
  end

  # Parses the sketch and checks the content it makes, the same way a save would.
  defp check(socket, %{"title" => title, "sketch" => sketch} = params) do
    parsed = Sketch.parse(sketch)
    content = Sketch.content(title, parsed)
    slug = Sketch.slug(title)

    assign(socket,
      form: to_form(params, as: :story),
      content: content,
      slug: slug,
      taken?: slug != "" and Stories.slug_taken?(slug),
      errors: if(parsed.errors == [], do: Validator.errors(content), else: parsed.errors)
    )
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
      <h1 class="text-2xl font-semibold tracking-tight">{gettext("New story")}</h1>
      <p class="text-sm text-base-content/70">
        {gettext(
          "Sketch the rooms and how they connect. Every exit also gets a way back, unless you mark it (one-way). The details come later, in the editor."
        )}
      </p>

      <.form for={@form} id="new-story-form" phx-change="check" phx-submit="create" class="space-y-3">
        <.input
          field={@form[:title]}
          type="text"
          label={gettext("Title")}
          phx-debounce="300"
          required
        />
        <p :if={@slug != ""} id="story-slug" class="text-sm text-base-content/70">
          {gettext("Its address: /stories/%{slug}", slug: @slug)}
          <span :if={@taken?} class="text-error">{gettext("is already taken.")}</span>
        </p>
        <.input
          field={@form[:sketch]}
          type="textarea"
          label={gettext("Sketch")}
          phx-debounce="300"
          spellcheck="false"
          class="w-full textarea min-h-80 font-mono text-sm"
        />

        <ul :if={@errors != []} id="sketch-errors" class="space-y-1 font-mono text-sm text-error">
          <li :for={error <- @errors}>{error}</li>
        </ul>
        <p :if={@errors == []} id="sketch-summary" class="text-sm text-success">
          {summary(@content)}
        </p>

        <.button
          id="create-story"
          variant="primary"
          disabled={@errors != [] or @slug == "" or @taken?}
          phx-disable-with={gettext("Creating...")}
        >
          {gettext("Create the story")}
        </.button>
      </.form>
    </Layouts.app>
    """
  end

  defp summary(content) do
    locations = Map.values(content["locations"])

    Enum.join(
      [
        ngettext("1 location", "%{count} locations", length(locations)),
        ngettext("1 exit", "%{count} exits", Enum.sum_by(locations, &map_size(&1["exits"]))),
        ngettext("1 item", "%{count} items", Enum.sum_by(locations, &length(&1["items"] || []))),
        ngettext("1 action", "%{count} actions", map_size(content["actions"] || %{})),
        ngettext("1 ending", "%{count} endings", length(content["endings"] || []))
      ],
      ", "
    ) <> "."
  end
end
