defmodule ChroniclesWeb.StoryUploadLive do
  @moduledoc """
  Upload a story's content as a JSON file, made by hand or by an AI tool. A new slug
  creates a private story; the slug of a story you manage gives it new content. Errors are
  listed so they can be fixed, or copied back into the tool that made the file.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Stories

  @impl true
  def mount(_params, _session, socket) do
    if Stories.can_write?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(page_title: gettext("Upload a story"), errors: [], replaces: nil)
       |> assign(form: to_form(%{"slug" => ""}))
       |> allow_upload(:story, accept: ~w(.json), max_entries: 1, max_file_size: 2_000_000)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Only authors can upload stories."))
       |> push_navigate(to: ~p"/stories")}
    end
  end

  @impl true
  def handle_event("validate", %{"slug" => slug}, socket) do
    # Until the author types one, the slug is the file's name.
    slug =
      case {slug, socket.assigns.uploads.story.entries} do
        {"", [entry | _]} -> Path.basename(entry.client_name, ".json")
        _ -> slug
      end

    {:noreply,
     assign(socket,
       form: to_form(%{"slug" => slug}),
       replaces: replaces(socket, slug),
       errors: []
     )}
  end

  def handle_event("save", %{"slug" => slug}, socket) do
    files =
      consume_uploaded_entries(socket, :story, fn %{path: path}, _ -> {:ok, File.read!(path)} end)

    case files do
      [] -> {:noreply, assign(socket, errors: [gettext("Choose a JSON file first.")])}
      [json] -> save(socket, slug, Jason.decode(json))
    end
  end

  defp save(socket, slug, {:ok, %{} = content}) do
    # Files from before slugs moved out of the content still carry a story_id.
    case Stories.save_story(socket.assigns.current_scope, slug, Map.delete(content, "story_id")) do
      {:ok, story} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("%{slug} is saved.", slug: story.slug))
         |> push_navigate(to: ~p"/stories/#{story.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, errors: messages(changeset))}

      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, errors: [gettext("Another author already has a story with this slug.")])}
    end
  end

  defp save(socket, _slug, _not_an_object),
    do: {:noreply, assign(socket, errors: [gettext("This file is not a JSON object.")])}

  # The story this upload would give new content, when the user manages it.
  defp replaces(socket, slug) do
    scope = socket.assigns.current_scope

    case Stories.find_story(scope, slug) do
      nil -> nil
      story -> if Stories.can_manage?(scope, story), do: story
    end
  end

  defp messages(changeset) do
    for {field, {message, _}} <- changeset.errors do
      if field == :content, do: message, else: "#{field} #{message}"
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
      <h1 class="text-2xl font-semibold tracking-tight">{gettext("Upload a story")}</h1>
      <p class="text-sm text-base-content/70">
        {gettext(
          "A new slug makes a new, private story. The slug of one of your stories gives it new content; games in progress keep the content they started with."
        )}
      </p>

      <section id="story-kit" class="space-y-2 rounded-2xl bg-base-200 p-4">
        <p class="text-sm">
          {gettext(
            "Write a story as a JSON file, by hand or with an AI tool like ChatGPT, Gemini or Claude. Give the tool the format and the schema, or the skill if it supports skills. Then upload the file it makes."
          )}
        </p>
        <div class="flex flex-wrap gap-2">
          <.button href={~p"/story-kit/story-format.md"} download size="sm">
            <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Format")}
          </.button>
          <.button href={~p"/story-kit/story-schema.json"} download size="sm">
            <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Schema")}
          </.button>
          <.button href={~p"/story-kit/chronicles-story.zip"} download size="sm">
            <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Skill")}
          </.button>
        </div>
      </section>

      <.form for={@form} id="upload-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <div
          phx-drop-target={@uploads.story.ref}
          class="rounded-2xl border-2 border-dashed border-base-300 p-6 text-center transition hover:border-primary"
        >
          <.live_file_input upload={@uploads.story} class="text-sm" />
          <p :for={entry <- @uploads.story.entries} class="mt-2 text-sm">{entry.client_name}</p>
          <p :for={error <- upload_errors(@uploads.story)} class="mt-2 text-sm text-error">
            {upload_error(error)}
          </p>
        </div>

        <.input
          field={@form[:slug]}
          type="text"
          label={gettext("Slug (in the story's URL)")}
          required
        />

        <p :if={@replaces} id="replaces" class="rounded-xl bg-base-200 p-3 text-sm">
          {gettext("This gives %{title} new content.", title: Stories.title(@replaces))}
        </p>

        <.button
          id="upload-button"
          variant="primary"
          phx-disable-with={gettext("Saving...")}
          data-confirm={@replaces && gettext("Give this story new content?")}
        >
          {gettext("Upload")}
        </.button>
      </.form>

      <section :if={@errors != []} id="upload-errors" class="space-y-2">
        <div class="flex items-center justify-between gap-4">
          <h2 class="font-semibold text-error">{gettext("The story was not saved")}</h2>
          <.button
            id="copy-errors"
            phx-hook=".CopyErrors"
            data-from="upload-error-list"
            size="sm"
            variant="ghost"
            class="group"
          >
            <span class="inline-flex items-center gap-1 group-data-copied:hidden">
              <.icon name="hero-clipboard" class="size-4" /> {gettext("Copy")}
            </span>
            <span class="hidden items-center gap-1 group-data-copied:inline-flex">
              <.icon name="hero-check" class="size-4" /> {gettext("Copied")}
            </span>
          </.button>
        </div>
        <ul id="upload-error-list" class="list-disc space-y-1 pl-5 font-mono text-sm select-all">
          <li :for={error <- @errors}>{error}</li>
        </ul>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyErrors">
          export default {
            mounted() {
              this.el.addEventListener("click", async () => {
                const list = document.getElementById(this.el.dataset.from)
                try {
                  await navigator.clipboard.writeText(list.innerText)
                } catch {
                  // No clipboard access: select the text, so the reader can copy it.
                  getSelection().selectAllChildren(list)
                  return
                }
                this.el.dataset.copied = ""
                clearTimeout(this.timer)
                this.timer = setTimeout(() => delete this.el.dataset.copied, 2000)
              })
            },
          }
        </script>
      </section>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: gettext("The file is too large.")
  defp upload_error(:not_accepted), do: gettext("Choose a .json file.")
  defp upload_error(:too_many_files), do: gettext("Choose one file.")
  defp upload_error(_), do: gettext("The file could not be read.")
end
