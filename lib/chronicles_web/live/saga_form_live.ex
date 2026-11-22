defmodule ChroniclesWeb.SagaFormLive do
  @moduledoc """
  Create or edit a saga: its title and its chapters in order. The saga checks run on every
  change, and between each two chapters the page shows how the endings of the one hand on
  to the next, with links to fix either side in the story editor. Saving is only possible
  when nothing is wrong.

  "Edit link" opens the link editor for two chapters: the output of each ending of the one
  and the input of the next, checked as you type. "Save link" saves both chapters at once
  (`Chronicles.Stories.save_stories/2`), apart from the saga itself.

  The chapters are a plain list, not a stream: a saga has a handful, every change reorders
  them, and each link between two chapters needs both.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Stories
  alias Chronicles.Stories.{Authoring, Saga, Sketch, Validator}

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    case load(scope, socket.assigns.live_action, params) do
      {:ok, saga} ->
        {:ok,
         socket
         |> assign(
           saga: saga,
           new?: is_nil(saga.id),
           candidates: Stories.chapter_candidates(scope)
         )
         |> assign(page_title: page_title(saga))
         |> assign(chapters: Enum.map(saga.chapters, & &1.story), link: nil, preview: nil)
         |> put_title(saga.title || "")
         |> add_new_chapter(params["add"])}

      {:error, message, to} ->
        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: to)}
    end
  end

  defp load(scope, :new, _params) do
    if Stories.can_write?(scope),
      do: {:ok, %Saga{chapters: []}},
      else: {:error, gettext("Only authors can make sagas."), ~p"/stories"}
  end

  defp load(scope, :edit, %{"slug" => slug}) do
    saga = Stories.get_saga(slug) || raise Ecto.NoResultsError, queryable: Saga

    if Stories.can_manage_saga?(scope, saga),
      do: {:ok, saga},
      else: {:error, gettext("Only the author can edit this saga."), ~p"/sagas/#{slug}"}
  end

  defp page_title(%Saga{id: nil}), do: gettext("New saga")
  defp page_title(saga), do: gettext("Edit %{title}", title: saga.title)

  ## Events

  @impl true
  def handle_event("title", %{"saga" => %{"title" => title}}, socket),
    do: {:noreply, put_title(socket, title)}

  def handle_event("add", %{"chapter" => %{"story" => id}}, socket) do
    story = Enum.find(socket.assigns.candidates, &(to_string(&1.id) == id))
    {:noreply, put_chapters(socket, socket.assigns.chapters ++ List.wrap(story))}
  end

  def handle_event("move", %{"index" => index, "by" => by}, socket) do
    {i, j} = {String.to_integer(index), String.to_integer(index) + String.to_integer(by)}
    chapters = socket.assigns.chapters

    if j in 0..(length(chapters) - 1)//1 do
      a = Enum.at(chapters, i)
      b = Enum.at(chapters, j)

      {:noreply, put_chapters(socket, chapters |> List.replace_at(i, b) |> List.replace_at(j, a))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove", %{"index" => index}, socket) do
    chapters = List.delete_at(socket.assigns.chapters, String.to_integer(index))
    {:noreply, put_chapters(socket, chapters)}
  end

  def handle_event("edit_link", %{"index" => index}, socket),
    do: {:noreply, open_link(socket, String.to_integer(index))}

  def handle_event("close_link", _params, socket),
    do: {:noreply, assign(socket, link: nil, preview: nil)}

  def handle_event("link_change", params, socket) do
    link = %{socket.assigns.link | outputs: params["outputs"] || %{}, input: params["input"]}
    {:noreply, put_link(socket, link)}
  end

  def handle_event("generate", _params, socket) do
    schema = Authoring.input_schema(socket.assigns.preview.from_content)
    input = if schema, do: Jason.encode!(schema, pretty: true), else: ""

    {:noreply,
     put_link(socket, %{socket.assigns.link | input: input, rev: socket.assigns.link.rev + 1})}
  end

  def handle_event("save_link", _params, socket) do
    %{current_scope: scope, preview: preview} = socket.assigns

    if preview.problems == [] do
      changes = [{preview.from, preview.from_content}, {preview.to, preview.to_content}]

      case Stories.save_stories(scope, changes) do
        {:ok, _stories} ->
          candidates = Stories.chapter_candidates(scope)

          fresh =
            Enum.map(
              socket.assigns.chapters,
              &(Enum.find(candidates, fn c -> c.id == &1.id end) || &1)
            )

          {:noreply,
           socket
           |> assign(candidates: candidates, link: nil, preview: nil)
           |> put_chapters(fresh)
           |> put_flash(:info, gettext("The link is saved, in both chapters."))}

        {:error, %Ecto.Changeset{} = changeset} ->
          problems = for {_, {message, _}} <- changeset.errors, do: message
          {:noreply, assign(socket, preview: %{preview | problems: problems})}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, gettext("You may not change both chapters."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save", _params, socket) do
    %{current_scope: scope, slug: slug, title: title, chapters: chapters} = socket.assigns

    if savable?(socket.assigns) do
      case Stories.save_saga(scope, slug, %{"title" => title, "stories" => slugs(chapters)}) do
        {:ok, saga} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("%{title} is saved.", title: saga.title))
           |> push_navigate(to: ~p"/sagas/#{saga.slug}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           assign(socket, errors: for({_, {message, _}} <- changeset.errors, do: message))}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, gettext("You may not change this saga."))}
      end
    else
      {:noreply, socket}
    end
  end

  ## State

  defp put_title(socket, title) do
    saga = socket.assigns.saga
    slug = if saga.id, do: saga.slug, else: Sketch.slug(title)

    socket
    |> assign(title: title, slug: slug, form: to_form(%{"title" => title}, as: :saga))
    |> assign(taken?: is_nil(saga.id) and slug != "" and Stories.saga_slug_taken?(slug))
    |> put_chapters(socket.assigns[:chapters] || [])
  end

  defp put_chapters(socket, chapters) do
    %{current_scope: scope, saga: saga} = socket.assigns

    socket
    |> assign(chapters: chapters, errors: Stories.saga_errors(scope, saga, slugs(chapters)))
    |> assign(add_form: to_form(%{"story" => ""}, as: :chapter))
    |> then(
      &if(chapters == socket.assigns[:chapters],
        do: &1,
        else: assign(&1, link: nil, preview: nil)
      )
    )
  end

  # Back from "Write a new chapter" (`?add=<slug>`): the new story goes at the end, not
  # saved yet, with the link editor open on it. A story without input gets one generated
  # from the endings before it, so the link can be valid at once.
  defp add_new_chapter(socket, nil), do: socket

  defp add_new_chapter(socket, slug) do
    %{candidates: candidates, chapters: chapters} = socket.assigns
    story = Enum.find(candidates, &(&1.slug == slug))

    if story && chapters != [] && not Enum.any?(chapters, &(&1.id == story.id)) do
      socket = socket |> put_chapters(chapters ++ [story]) |> open_link(length(chapters) - 1)

      if story.head_version.content["input"],
        do: socket,
        else: elem(handle_event("generate", %{}, socket), 1)
    else
      socket
    end
  end

  # The link editor for chapter `at` and the one after it, filled with what they have now.
  defp open_link(socket, at) do
    from = Enum.at(socket.assigns.chapters, at)
    to = Enum.at(socket.assigns.chapters, at + 1)
    input = to.head_version.content["input"]

    outputs =
      for {ending, i} <- Enum.with_index(from.head_version.content["endings"] || []),
          into: %{},
          do: {to_string(i), if(ending["output"], do: Jason.encode!(ending["output"]), else: "")}

    link = %{
      at: at,
      outputs: outputs,
      input: if(input, do: Jason.encode!(input["schema"], pretty: true), else: ""),
      rev: 0
    }

    put_link(socket, link)
  end

  # The texts as typed, turned into the two chapters' new content and checked: JSON that
  # doesn't parse, the story checks of both, and per ending whether it opens the next.
  defp put_link(socket, link) do
    from = Enum.at(socket.assigns.chapters, link.at)
    to = Enum.at(socket.assigns.chapters, link.at + 1)
    endings = from.head_version.content["endings"] || []

    {endings, output_errors} =
      endings
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {ending, i}, errors ->
        case decode(link.outputs[to_string(i)] || "") do
          {:ok, nil} ->
            {Map.delete(ending, "output"), errors}

          {:ok, output} ->
            {Map.put(ending, "output", output), errors}

          :error ->
            {ending,
             errors ++ [gettext("The output of ending %{n} is not valid JSON.", n: i + 1)]}
        end
      end)

    {to_content, input_errors} =
      case decode(link.input || "") do
        {:ok, nil} -> {Map.delete(to.head_version.content, "input"), []}
        {:ok, schema} -> {Map.put(to.head_version.content, "input", %{"schema" => schema}), []}
        :error -> {to.head_version.content, [gettext("The input is not valid JSON.")]}
      end

    from_content = Map.put(from.head_version.content, "endings", endings)
    n = link.at + 1

    problems =
      output_errors ++
        input_errors ++
        Enum.map(
          Validator.errors(from_content),
          &gettext("chapter %{n}: %{error}", n: n, error: &1)
        ) ++
        Enum.map(
          Validator.errors(to_content),
          &gettext("chapter %{n}: %{error}", n: n + 1, error: &1)
        )

    assign(socket,
      link: link,
      preview: %{
        from: from,
        to: to,
        from_content: from_content,
        to_content: to_content,
        endings: Validator.handover(from_content, to_content),
        fields: to_content["input"] && fields(to_content["input"]["schema"]),
        problems: problems
      }
    )
  end

  # Empty text means nothing: no output, or no input.
  defp decode(text) do
    if String.trim(text) == "" do
      {:ok, nil}
    else
      case Jason.decode(text) do
        {:ok, value} -> {:ok, value}
        {:error, _} -> :error
      end
    end
  end

  defp slugs(chapters), do: Enum.map(chapters, & &1.slug)

  defp savable?(assigns),
    do:
      assigns.errors == [] and String.trim(assigns.title) != "" and assigns.slug != "" and
        not assigns.taken?

  # The stories to offer in "Add chapter": those not in the saga yet. One that can't be a
  # chapter here is offered disabled, with the reason.
  defp options(candidates, chapters, saga) do
    in_saga = MapSet.new(chapters, & &1.id)
    visibility = if chapters != [], do: hd(chapters).visibility

    for story <- candidates, not MapSet.member?(in_saga, story.id) do
      reason =
        cond do
          story.chapter && story.chapter.saga_id != saga.id ->
            gettext("in the saga %{title}", title: story.chapter.saga.title)

          visibility && story.visibility != visibility ->
            if story.visibility == :public,
              do: gettext("public, the saga is private"),
              else: gettext("private, the saga is public")

          true ->
            nil
        end

      label = if reason, do: "#{Stories.title(story)} (#{reason})", else: Stories.title(story)
      [key: label, value: story.id, disabled: !!reason]
    end
  end

  # Each chapter with the one after it (nil for the last), for the links between them.
  defp rows(chapters), do: Enum.zip([chapters, tl(chapters ++ [nil]), 0..length(chapters)])

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link
        navigate={if(@new?, do: ~p"/stories", else: ~p"/sagas/#{@saga.slug}")}
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-primary"
      >
        <.icon name="hero-chevron-left" class="size-4" />
        {if(@new?, do: gettext("Stories"), else: @saga.title)}
      </.link>
      <h1 class="text-3xl font-semibold tracking-tight">{@page_title}</h1>

      <.form for={@form} id="saga-form" phx-change="title" phx-submit="save">
        <.input field={@form[:title]} label={gettext("Title")} phx-debounce="300" autocomplete="off" />
        <p :if={@new? and @slug != ""} id="saga-slug" class="-mt-1 text-xs text-base-content/60">
          <%= if @taken? do %>
            <span class="text-error">
              {gettext("Another saga already uses the address /sagas/%{slug}.", slug: @slug)}
            </span>
          <% else %>
            {gettext("Address: /sagas/%{slug}", slug: @slug)}
          <% end %>
        </p>
      </.form>

      <section class="space-y-3">
        <h2 class="text-lg font-semibold">{gettext("Chapters")}</h2>
        <p :if={@chapters == []} id="no-chapters" class="text-sm text-base-content/60">
          {gettext("No chapters yet. Add the stories of this saga in the order they are played.")}
        </p>
        <ol id="saga-chapters" class="grid gap-2">
          <li :for={{story, next, i} <- rows(@chapters)} id={"chapter-#{story.id}"} class="space-y-2">
            <div class="flex items-center gap-3 rounded-xl border border-base-300 bg-base-100 px-3 py-2">
              <span class="w-6 text-center text-lg font-semibold tabular-nums text-base-content/40">
                {i + 1}
              </span>
              <span class="flex-1 font-medium">{Stories.title(story)}</span>
              <.icon
                :if={story.visibility == :private}
                name="hero-lock-closed"
                class="size-4 text-base-content/50"
              />
              <div class="flex gap-1">
                <.button
                  id={"up-#{story.id}"}
                  phx-click="move"
                  phx-value-index={i}
                  phx-value-by="-1"
                  disabled={i == 0}
                  variant="ghost"
                  size="sm"
                  aria-label={gettext("Move up")}
                >
                  <.icon name="hero-arrow-up" class="size-4" />
                </.button>
                <.button
                  id={"down-#{story.id}"}
                  phx-click="move"
                  phx-value-index={i}
                  phx-value-by="1"
                  disabled={is_nil(next)}
                  variant="ghost"
                  size="sm"
                  aria-label={gettext("Move down")}
                >
                  <.icon name="hero-arrow-down" class="size-4" />
                </.button>
                <.button
                  id={"remove-#{story.id}"}
                  phx-click="remove"
                  phx-value-index={i}
                  variant="ghost"
                  size="sm"
                  aria-label={gettext("Remove from the saga")}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </.button>
              </div>
            </div>
            <%= cond do %>
              <% is_nil(next) -> %>
              <% @link && @link.at == i -> %>
                <.link_editor link={@link} preview={@preview} n={i + 1} />
              <% true -> %>
                <.handover from={story} to={next} n={i + 1} />
            <% end %>
          </li>
        </ol>

        <.form
          for={@add_form}
          id="add-chapter-form"
          phx-submit="add"
          class="flex flex-wrap items-end gap-2"
        >
          <div class="min-w-64 flex-1">
            <.input
              field={@add_form[:story]}
              type="select"
              label={gettext("Add a chapter")}
              prompt={gettext("Choose one of your stories")}
              options={options(@candidates, @chapters, @saga)}
            />
          </div>
          <%!-- mb-3: the select's fieldset has 4px padding below its mb-2. --%>
          <.button id="add-chapter" size="sm" class="mb-3">
            <.icon name="hero-plus" class="size-4" /> {gettext("Add")}
          </.button>
          <%!-- Only for a saved saga with chapters: an unsaved one would be lost. --%>
          <.button
            :if={not @new? and @saga.chapters != []}
            id="write-chapter"
            navigate={~p"/stories/new?#{[saga: @saga.slug]}"}
            size="sm"
            class="mb-3"
          >
            <.icon name="hero-pencil-square" class="size-4" /> {gettext("Write a new chapter")}
          </.button>
        </.form>
      </section>

      <%!-- Not on an empty saga: "no chapters yet" already says what is missing. --%>
      <ul
        :if={@errors != [] and @chapters != []}
        id="saga-errors"
        class="list-disc space-y-1 rounded-xl bg-error/10 p-4 pl-8 font-mono text-xs text-error"
      >
        <li :for={error <- @errors}>{error}</li>
      </ul>

      <div class="flex gap-2">
        <.button id="save-saga" phx-click="save" variant="primary" disabled={!savable?(assigns)}>
          {if(@new?, do: gettext("Create saga"), else: gettext("Save"))}
        </.button>
      </div>
    </Layouts.app>
    """
  end

  attr :from, :map, required: true
  attr :to, :map, required: true
  attr :n, :integer, required: true, doc: "the chapter number of `from`"

  # How the endings of one chapter hand on to the next: per ending, whether it unlocks the
  # next chapter, with links to fix either side in the story editor.
  defp handover(assigns) do
    content = assigns.to.head_version.content

    assigns =
      assign(assigns,
        input: content["input"],
        fields: content["input"] && fields(content["input"]["schema"]),
        endings: Validator.handover(assigns.from.head_version.content, content)
      )

    ~H"""
    <div
      id={"handover-#{@from.id}"}
      class="ml-4 space-y-2 border-l-2 border-dashed border-base-300 py-1 pl-6 text-sm"
    >
      <%= if @input do %>
        <div class="space-y-1">
          <p class="text-base-content/70">{gettext("How chapter %{n} can end", n: @n)}</p>
          <ul class="space-y-1.5">
            <li
              :for={{ending, accepted?} <- @endings}
              class="grid grid-cols-[3rem_1fr] items-baseline gap-x-3 gap-y-0.5 sm:grid-cols-[3rem_1fr_8rem_10.5rem]"
            >
              <span class="rounded bg-base-200 px-1.5 text-center text-xs font-medium text-base-content/70">
                {if(ending["outcome"] == "win", do: gettext("Win"), else: gettext("Loss"))}
              </span>
              <span class="text-base-content/80">{ending["message"]}</span>
              <span class="col-start-2 text-xs text-base-content/60 sm:col-start-auto">
                {gettext("hands on")}
                <code class="font-mono text-base-content/80">{output(ending["output"])}</code>
              </span>
              <.result
                outcome={ending["outcome"]}
                accepted?={accepted?}
                next={@n + 1}
              />
            </li>
          </ul>
        </div>
        <div class="space-y-1">
          <p class="text-base-content/70">{gettext("Chapter %{n} needs:", n: @n + 1)}</p>
          <ul :if={@fields} class="space-y-0.5">
            <li :for={{name, details} <- @fields}>
              <code class="font-mono text-xs font-semibold">{name}</code>
              <span class="text-base-content/70">· {details}</span>
            </li>
          </ul>
          <details open={is_nil(@fields)} class="text-xs">
            <summary class="cursor-pointer text-base-content/60">{gettext("JSON Schema")}</summary>
            <pre class="mt-1 max-h-48 overflow-auto rounded-lg bg-base-200 px-3 py-2 font-mono"><%= Jason.encode!(@input["schema"], pretty: true) %></pre>
          </details>
        </div>
      <% else %>
        <p class="text-error">
          {gettext("Chapter %{n} takes no input, so nothing links it to chapter %{m}.",
            n: @n + 1,
            m: @n
          )}
        </p>
      <% end %>
      <p class="flex flex-wrap items-center gap-3 text-xs">
        <.button
          id={"edit-link-#{@from.id}"}
          type="button"
          phx-click="edit_link"
          phx-value-index={@n - 1}
          size="sm"
        >
          <.icon name="hero-link" class="size-4" /> {gettext("Edit link")}
        </.button>
        <.link
          navigate={~p"/stories/#{@from.slug}/edit?part=endings"}
          class="underline transition hover:text-primary"
        >
          {gettext("Edit the endings of chapter %{n}", n: @n)}
        </.link>
        <.link
          navigate={~p"/stories/#{@to.slug}/edit?part=story"}
          class="underline transition hover:text-primary"
        >
          {gettext("Edit the input of chapter %{n}", n: @n + 1)}
        </.link>
      </p>
    </div>
    """
  end

  attr :link, :map, required: true
  attr :preview, :map, required: true
  attr :n, :integer, required: true, doc: "the chapter number of the first of the two"

  # Both halves of the link, editable: each ending's output, and the next chapter's input.
  defp link_editor(assigns) do
    ~H"""
    <.form
      for={to_form(%{}, as: :link)}
      id="link-form"
      phx-change="link_change"
      phx-submit="save_link"
      class="ml-4 space-y-4 rounded-xl border border-primary/40 bg-base-100 p-4 text-sm"
    >
      <div class="space-y-2">
        <p class="font-medium">{gettext("How chapter %{n} can end", n: @n)}</p>
        <ul class="space-y-2">
          <li
            :for={{{ending, accepted?}, i} <- Enum.with_index(@preview.endings)}
            class="grid grid-cols-[3rem_1fr] items-baseline gap-x-3 gap-y-1"
          >
            <span class="rounded bg-base-200 px-1.5 text-center text-xs font-medium text-base-content/70">
              {if(ending["outcome"] == "win", do: gettext("Win"), else: gettext("Loss"))}
            </span>
            <span class="text-base-content/80">{ending["message"]}</span>
            <div class="col-start-2 flex flex-wrap items-center gap-x-3 gap-y-1">
              <label class="flex min-w-56 flex-1 items-center gap-2 text-xs text-base-content/60">
                {gettext("hands on")}
                <input
                  type="text"
                  id={"link-output-#{i}"}
                  name={"outputs[#{i}]"}
                  value={@link.outputs[to_string(i)]}
                  placeholder={gettext("nothing")}
                  spellcheck="false"
                  autocomplete="off"
                  phx-debounce="300"
                  class="input input-sm flex-1 font-mono text-xs"
                />
              </label>
              <%!-- A fixed width, so the output fields line up from row to row. --%>
              <div class="shrink-0 sm:w-44">
                <.result outcome={ending["outcome"]} accepted?={accepted?} next={@n + 1} />
              </div>
            </div>
          </li>
        </ul>
      </div>

      <div class="space-y-2">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="font-medium">{gettext("Chapter %{n} needs", n: @n + 1)}</p>
          <.button id="generate-input" type="button" phx-click="generate" size="sm">
            <.icon name="hero-sparkles" class="size-4" /> {gettext("Generate from the endings")}
          </.button>
        </div>
        <textarea
          id={"link-input-#{@link.rev}"}
          name="input"
          rows="8"
          spellcheck="false"
          phx-debounce="400"
          placeholder={gettext("No input: empty means this chapter takes none.")}
          class="textarea w-full font-mono text-xs"
        >{@link.input}</textarea>
        <ul :if={@preview.fields} class="space-y-0.5">
          <li :for={{name, details} <- @preview.fields}>
            <code class="font-mono text-xs font-semibold">{name}</code>
            <span class="text-base-content/70">· {details}</span>
          </li>
        </ul>
      </div>

      <p
        :if={@preview.from.draft || @preview.to.draft}
        id="link-draft-note"
        class="rounded-lg bg-warning/10 p-3 text-xs text-warning"
      >
        {gettext(
          "One of these chapters has unsaved work in the story editor. Saving the link saves a new version without it."
        )}
      </p>

      <ul
        :if={@preview.problems != []}
        id="link-problems"
        class="list-disc space-y-1 rounded-lg bg-error/10 p-3 pl-7 font-mono text-xs text-error"
      >
        <li :for={problem <- @preview.problems}>{problem}</li>
      </ul>

      <div class="flex gap-2">
        <.button id="save-link" variant="primary" size="sm" disabled={@preview.problems != []}>
          {gettext("Save link")}
        </.button>
        <.button id="cancel-link" type="button" phx-click="close_link" variant="ghost" size="sm">
          {gettext("Cancel")}
        </.button>
      </div>
    </.form>
    """
  end

  # A short summary of an input schema: each top-level property with its type, range or
  # choices, and whether it is required. Nil for a schema that isn't an object of
  # properties; the page then shows the JSON.
  defp fields(%{"properties" => properties} = schema) when is_map(properties) do
    required = schema["required"] || []

    for {name, property} <- Enum.sort(properties) do
      details =
        [
          property["type"] && property["type"] |> List.wrap() |> Enum.join(" or "),
          range(property),
          property["enum"] && Enum.map_join(property["enum"], " | ", &Jason.encode!/1),
          name in required && gettext("required")
        ]
        |> Enum.filter(& &1)
        |> Enum.join(", ")

      {name, details}
    end
  end

  defp fields(_schema), do: nil

  defp range(%{"minimum" => min, "maximum" => max}), do: "#{min}–#{max}"
  defp range(%{"minimum" => min}), do: "≥ #{min}"
  defp range(%{"maximum" => max}), do: "≤ #{max}"
  defp range(_property), do: nil

  # An ending's output, readable: `spare: 3, name: "Ada"`, or "nothing".
  defp output(nil), do: gettext("nothing")

  defp output(%{} = output),
    do:
      Enum.map_join(Enum.sort(output), ", ", fn {key, value} ->
        "#{key}: #{Jason.encode!(value)}"
      end)

  defp output(output), do: Jason.encode!(output)

  attr :outcome, :string, required: true
  attr :accepted?, :boolean, required: true
  attr :next, :integer, required: true, doc: "the number of the next chapter"

  # What an ending does to the next chapter. A loss must never open it; a win may, and at
  # least one win must (the saga errors say so when none does).
  defp result(assigns) do
    ~H"""
    <span class={[
      "col-start-2 inline-flex items-center gap-1 text-xs font-medium sm:col-start-auto",
      cond do
        @outcome == "loss" and @accepted? -> "text-error"
        @outcome == "loss" or @accepted? -> "text-success"
        true -> "text-base-content/50"
      end
    ]}>
      <%= cond do %>
        <% @outcome == "loss" and @accepted? -> %>
          <.icon name="hero-x-mark-mini" class="size-3.5" />
          {gettext("opens chapter %{n}, but a loss shouldn't", n: @next)}
        <% @outcome == "loss" -> %>
          <.icon name="hero-check-mini" class="size-3.5" />
          {gettext("chapter %{n} stays locked", n: @next)}
        <% @accepted? -> %>
          <.icon name="hero-check-mini" class="size-3.5" /> {gettext("opens chapter %{n}", n: @next)}
        <% true -> %>
          <.icon name="hero-minus-mini" class="size-3.5" />
          {gettext("doesn't open chapter %{n}", n: @next)}
      <% end %>
    </span>
    """
  end
end
