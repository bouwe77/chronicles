defmodule ChroniclesWeb.EditStoryLive do
  @moduledoc """
  Edit a story part by part, as JSON, with the same checks as a save. Saving makes a new
  head version, so games in progress keep theirs.

  Unsaved work is kept as the story's draft after every change, so it survives a reload,
  a lost connection or a deploy. Saving or discarding clears it. Text that isn't valid
  JSON yet is not kept.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Stories
  alias Chronicles.Stories.{Authoring, Validator}

  @parts %{
    "story" => :story,
    "context" => :context,
    "items" => :items,
    "supplies" => :supplies,
    "timeline" => :timeline,
    "rules" => :rules,
    "endings" => :endings,
    "all" => :all
  }

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope
    story = Stories.get_story!(scope, slug)

    if Stories.can_manage?(scope, story) do
      {:ok,
       socket
       |> assign(page_title: gettext("Edit %{title}", title: Stories.title(story)), story: story)
       |> assign(saved: story.head_version.content, find: "", rev: 0, tool_error: nil)
       |> assign(save_errors: [])
       |> put_content(story.draft || story.head_version.content)
       |> select_part(:story)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Only the author can edit this story."))
       |> push_navigate(to: ~p"/stories/#{slug}")}
    end
  end

  ## Events

  @impl true
  def handle_event("select", %{"part" => part}, socket),
    do: {:noreply, select_part(socket, decode(part))}

  # Every edit that is valid JSON of the right type goes into the content at once; the
  # validator then lists what is still wrong. Invalid JSON only shows its error. The
  # text itself is not assigned: the browser already has it, so it isn't sent back.
  def handle_event("edit", %{"text" => text}, socket) do
    result =
      with {:ok, fragment} <- Jason.decode(text),
           do: Authoring.put_fragment(socket.assigns.content, socket.assigns.part, fragment)

    case result do
      {:ok, content} ->
        {:noreply, socket |> assign(text_error: nil) |> put_content(content)}

      {:error, %Jason.DecodeError{} = error} ->
        {:noreply, assign(socket, text_error: Exception.message(error))}

      {:error, message} ->
        {:noreply, assign(socket, text_error: message)}
    end
  end

  # A new location or action goes into the content at once, from its template.
  def handle_event("add", %{"kind" => kind, "new_id" => id}, socket)
      when kind in ~w(location action) do
    content = socket.assigns.content
    id = String.trim(id)
    part = {String.to_existing_atom(kind), id}

    cond do
      id == "" ->
        {:noreply, assign(socket, tool_error: gettext("Give it an id first."))}

      id in ids(content, kind <> "s") ->
        {:noreply, assign(socket, tool_error: gettext("%{id} is already taken.", id: id))}

      true ->
        {:ok, content} = Authoring.put_fragment(content, part, Authoring.fragment(content, part))
        {:noreply, socket |> put_content(content) |> select_part(part)}
    end
  end

  def handle_event("rename", %{"to" => to}, socket) do
    {:location, from} = socket.assigns.part
    to = String.trim(to)

    apply_tool(
      socket,
      Authoring.rename_location(socket.assigns.content, from, to),
      {:location, to}
    )
  end

  def handle_event("connect", %{"to" => to, "label" => label, "back" => back}, socket) do
    {:location, from} = part = socket.assigns.part

    result =
      Authoring.connect(socket.assigns.content, from, to, String.trim(label), String.trim(back))

    apply_tool(socket, result, part)
  end

  def handle_event("remove", _params, socket) do
    result =
      case socket.assigns.part do
        {:location, id} ->
          with {:ok, content, _removed} <- Authoring.remove_location(socket.assigns.content, id),
               do: {:ok, content}

        {:action, id} ->
          Authoring.remove_action(socket.assigns.content, id)
      end

    apply_tool(socket, result, :story)
  end

  # A story switch, shown as a checkbox: off removes the key, because false is its default.
  def handle_event("toggle_notes", _params, socket) do
    content = socket.assigns.content

    content =
      if content["notesEnabled"],
        do: Map.delete(content, "notesEnabled"),
        else: Map.put(content, "notesEnabled", true)

    {:noreply, socket |> put_content(content) |> select_part(socket.assigns.part)}
  end

  def handle_event("find", %{"find" => find}, socket),
    do: {:noreply, socket |> assign(find: find) |> assign_uses()}

  def handle_event("find_uses", _params, socket),
    do: {:noreply, socket |> assign(find: elem(socket.assigns.part, 1)) |> assign_uses()}

  def handle_event("save", _params, socket) do
    %{current_scope: scope, story: story, content: content} = socket.assigns

    case Stories.save_story(scope, story.slug, content) do
      {:ok, story} ->
        {:noreply,
         socket
         |> assign(story: story, saved: content, dirty?: false, save_errors: [])
         |> put_flash(:info, gettext("Saved. New games play this version."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, save_errors: for({_, {message, _}} <- changeset.errors, do: message))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("You may not change this story."))}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> put_content(socket.assigns.saved)
     |> select_part(:story)
     |> assign(save_errors: [])}
  end

  ## State

  defp apply_tool(socket, {:ok, content}, part),
    do: {:noreply, socket |> put_content(content) |> select_part(part)}

  defp apply_tool(socket, {:error, message}, _part),
    do: {:noreply, assign(socket, tool_error: message)}

  defp put_content(socket, content) do
    socket
    |> keep_draft(content)
    |> assign(
      content: content,
      errors: Validator.errors(content),
      rooms: rooms(content),
      dirty?: content != socket.assigns.saved
    )
    |> assign_uses()
  end

  # Where the find text is used; nil while it is empty.
  defp assign_uses(socket) do
    %{content: content, find: find} = socket.assigns
    find = String.trim(find)
    assign(socket, uses: if(find != "", do: Authoring.uses(content, find)))
  end

  # Not on mount: then the content comes from the story itself.
  defp keep_draft(%{assigns: %{content: old}} = socket, content) when old != content do
    %{current_scope: scope, story: story, saved: saved} = socket.assigns
    draft = if content != saved, do: content

    case Stories.save_draft(scope, story, draft) do
      {:ok, story} -> assign(socket, story: story)
      {:error, _} -> put_flash(socket, :error, gettext("Could not keep your changes."))
    end
  end

  defp keep_draft(socket, _content), do: socket

  # The room badges. Work in progress can break the shape the summary reads; then the
  # badges are left out, and the error list says what is wrong.
  defp rooms(content) do
    Map.new(Authoring.summarize(content), &{&1.id, &1})
  rescue
    _ -> %{}
  end

  # A new `rev` makes a new textarea, so it shows `text` even when that equals the last
  # one sent: the edits typed since then never reached `@text`.
  defp select_part(socket, part) do
    text = socket.assigns.content |> Authoring.fragment(part) |> Jason.encode!(pretty: true)
    rev = socket.assigns.rev + 1
    assign(socket, part: part, text: text, rev: rev, text_error: nil, tool_error: nil)
  end

  defp decode("location:" <> id), do: {:location, id}
  defp decode("action:" <> id), do: {:action, id}
  defp decode(name), do: Map.fetch!(@parts, name)

  defp encode({kind, id}), do: "#{kind}:#{id}"
  defp encode(part), do: to_string(part)

  defp ids(content, key) do
    case content[key] do
      %{} = map -> map |> Map.keys() |> Enum.sort()
      _ -> []
    end
  end

  # The confirm question for removing the selected location or action.
  defp remove_question(content, {:location, id}) do
    case Authoring.remove_location(content, id) do
      {:ok, _content, []} ->
        gettext("Remove the location %{id}?", id: id)

      {:ok, _content, exits} ->
        gettext("Remove the location %{id}? These exits to it go too: %{exits}",
          id: id,
          exits: Enum.join(exits, ", ")
        )

      {:error, _} ->
        nil
    end
  end

  defp remove_question(_content, {:action, id}),
    do: gettext("Remove the action %{id}? It also leaves every location that shows it.", id: id)

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div id="editor" class="space-y-4">
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-2">
            <.link
              navigate={~p"/stories/#{@story.slug}"}
              class="rounded-full p-2 transition hover:bg-base-200"
              aria-label={gettext("Back to the story")}
            >
              <.icon name="hero-chevron-left" class="size-5" />
            </.link>
            <h1 class="text-2xl font-semibold tracking-tight">
              {@content["story_title"] || @story.slug}
            </h1>
            <span :if={@dirty?} id="unsaved" class="text-sm text-base-content/60">
              {gettext("unsaved")}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <.button
              :if={@dirty?}
              id="discard"
              phx-click="discard"
              variant="ghost"
              data-confirm={gettext("Discard your unsaved changes?")}
            >
              {gettext("Discard")}
            </.button>
            <.button
              id="save"
              phx-click="save"
              variant="primary"
              disabled={not @dirty? or @errors != [] or @text_error != nil}
            >
              {gettext("Save")}
            </.button>
          </div>
        </div>

        <div class="grid gap-4 lg:grid-cols-[16rem_minmax(0,1fr)]">
          <nav
            id="parts"
            class="space-y-4 self-start text-sm lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto lg:pr-1"
            aria-label={gettext("Parts of the story")}
          >
            <ul class="space-y-0.5">
              <li :for={{part, label} <- general_parts()}>
                <.part_button part={part} label={label} current={@part} text_error={@text_error} />
              </li>
            </ul>

            <.part_group
              title={gettext("Locations")}
              kind="location"
              ids={ids(@content, "locations")}
              rooms={@rooms}
              current={@part}
              text_error={@text_error}
            />
            <.part_group
              title={gettext("Actions")}
              kind="action"
              ids={ids(@content, "actions")}
              rooms={%{}}
              current={@part}
              text_error={@text_error}
            />

            <.part_button
              part={:all}
              label={gettext("Everything, as one JSON")}
              current={@part}
              text_error={@text_error}
            />
          </nav>

          <div class="min-w-0 space-y-3">
            <.toolbar part={@part} content={@content} />
            <p :if={@tool_error} id="tool-error" class="text-sm text-error">{@tool_error}</p>

            <.form for={to_form(%{"text" => @text})} id="part-form" phx-change="edit">
              <.input
                type="textarea"
                id={"part-text-#{@rev}"}
                name="text"
                value={@text}
                phx-debounce="400"
                spellcheck="false"
                aria-label={gettext("The selected part, as JSON")}
                class="w-full textarea min-h-[55vh] font-mono text-sm"
              />
            </.form>
            <p :if={@text_error} id="json-error" class="text-sm text-error">
              {gettext("Not valid JSON yet: %{message}", message: @text_error)}
            </p>

            <section id="problems" class="space-y-1">
              <%= if @errors == [] do %>
                <p class="text-sm text-success">{gettext("No problems found.")}</p>
              <% else %>
                <h2 class="text-sm font-semibold text-error">
                  {ngettext("1 problem", "%{count} problems", length(@errors))}
                </h2>
                <ul class="list-disc space-y-0.5 pl-5 font-mono text-xs text-error">
                  <li :for={error <- @errors}>{error}</li>
                </ul>
              <% end %>
              <ul :if={@save_errors != []} class="list-disc pl-5 font-mono text-xs text-error">
                <li :for={error <- @save_errors}>{error}</li>
              </ul>
            </section>

            <.form for={to_form(%{"find" => @find})} id="find-form" phx-change="find">
              <.input
                name="find"
                value={@find}
                label={gettext("Find uses of an id or a context path")}
                phx-debounce="300"
                spellcheck="false"
              />
            </.form>
            <ul :if={@uses not in [nil, []]} id="uses" class="space-y-0.5 font-mono text-xs">
              <li :for={use <- @uses}>{use}</li>
            </ul>
            <p :if={@uses == []} id="uses" class="text-sm text-base-content/60">
              {gettext("Not used anywhere.")}
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp general_parts do
    [
      story: gettext("Story"),
      context: gettext("Context"),
      items: gettext("Items"),
      supplies: gettext("Supplies"),
      timeline: gettext("Timeline"),
      rules: gettext("Rules"),
      endings: gettext("Endings")
    ]
  end

  attr :part, :any, required: true
  attr :label, :string, required: true
  attr :current, :any, required: true
  attr :text_error, :string, default: nil
  attr :room, :map, default: nil

  defp part_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"part-#{:erlang.phash2(@part)}"}
      phx-click="select"
      phx-value-part={encode(@part)}
      data-confirm={
        @text_error && gettext("This part has invalid JSON. Leave it and lose that edit?")
      }
      aria-current={@part == @current && "true"}
      title={@room && gettext("%{in} exits in, %{out} out", in: @room.in, out: @room.out)}
      class={[
        "flex w-full items-center gap-2 rounded-lg px-2 py-1 text-left transition",
        if(@part == @current,
          do: "bg-primary text-primary-content",
          else: "hover:bg-base-200"
        )
      ]}
    >
      <span class="truncate">{@label}</span>
      <span
        :if={@room && @room.start?}
        class="rounded-full bg-base-300 px-1.5 text-xs text-base-content"
      >
        {gettext("start")}
      </span>
      <span
        :if={@room && not @room.reachable?}
        class="rounded-full bg-warning px-1.5 text-xs text-warning-content"
      >
        {gettext("unreachable")}
      </span>
    </button>
    """
  end

  attr :title, :string, required: true
  attr :kind, :string, required: true
  attr :ids, :list, required: true
  attr :rooms, :map, required: true
  attr :current, :any, required: true
  attr :text_error, :string, default: nil

  defp part_group(assigns) do
    ~H"""
    <div>
      <h2 class="px-2 pb-1 text-xs font-semibold uppercase tracking-wider text-base-content/60">
        {@title}
      </h2>
      <ul class="space-y-0.5">
        <li :for={id <- @ids}>
          <.part_button
            part={{String.to_existing_atom(@kind), id}}
            label={id}
            current={@current}
            text_error={@text_error}
            room={@rooms[id]}
          />
        </li>
      </ul>
      <.form
        for={to_form(%{})}
        id={"add-#{@kind}"}
        phx-submit="add"
        class="flex items-start gap-1 px-2 pt-1"
      >
        <input type="hidden" name="kind" value={@kind} />
        <.input
          name="new_id"
          value=""
          placeholder={gettext("new id")}
          aria-label={gettext("The id of a new %{kind}", kind: @kind)}
          spellcheck="false"
        />
        <.button size="sm" aria-label={gettext("Add")}>+</.button>
      </.form>
    </div>
    """
  end

  attr :part, :any, required: true
  attr :content, :map, required: true

  defp toolbar(%{part: {:location, id}} = assigns) do
    assigns =
      assign(assigns,
        id: id,
        start?: id == assigns.content["starting_location"],
        others: ids(assigns.content, "locations") -- [id]
      )

    ~H"""
    <div id="toolbar" class="flex flex-wrap items-end gap-3">
      <.button id="find-uses" phx-click="find_uses" size="sm">{gettext("Find uses")}</.button>
      <.form for={to_form(%{})} id="rename-form" phx-submit="rename" class="flex items-end gap-1">
        <.input name="to" value={@id} label={gettext("Rename to")} spellcheck="false" />
        <.button size="sm" class="mb-2">{gettext("Rename")}</.button>
      </.form>
      <.form
        :if={@others != []}
        for={to_form(%{})}
        id="connect-form"
        phx-submit="connect"
        class="flex flex-wrap items-end gap-1"
      >
        <.input type="select" name="to" value="" options={@others} label={gettext("Connect to")} />
        <.input name="label" value="" label={gettext("Exit label")} />
        <.input name="back" value="" label={gettext("Way back (optional)")} />
        <.button size="sm" class="mb-2">{gettext("Connect")}</.button>
      </.form>
      <.button
        id="remove-part"
        phx-click="remove"
        disabled={@start?}
        title={@start? && gettext("The starting location can't be removed.")}
        data-confirm={remove_question(@content, {:location, @id})}
        variant="ghost"
        size="sm"
        class="mb-2"
      >
        <.icon name="hero-trash" class="size-4" /> {gettext("Remove")}
      </.button>
    </div>
    """
  end

  defp toolbar(%{part: {:action, id}} = assigns) do
    assigns = assign(assigns, id: id)

    ~H"""
    <div id="toolbar" class="flex flex-wrap items-center gap-2">
      <.button id="find-uses" phx-click="find_uses" size="sm">{gettext("Find uses")}</.button>
      <.button
        id="remove-part"
        phx-click="remove"
        data-confirm={remove_question(@content, {:action, @id})}
        variant="ghost"
        size="sm"
      >
        <.icon name="hero-trash" class="size-4" /> {gettext("Remove")}
      </.button>
    </div>
    """
  end

  defp toolbar(%{part: :story} = assigns) do
    ~H"""
    <div id="toolbar">
      <label class="inline-flex cursor-pointer items-center gap-2 text-sm">
        <input
          id="notes-enabled"
          type="checkbox"
          checked={@content["notesEnabled"] == true}
          phx-click="toggle_notes"
          class="checkbox checkbox-sm"
        />
        {gettext("Players get a notes panel")}
      </label>
    </div>
    """
  end

  defp toolbar(assigns), do: ~H""
end
