defmodule ChroniclesWeb.StoryKitController do
  @moduledoc """
  The files an AI tool needs to write a story: the format, its JSON Schema, and a skill
  that bundles both. Read at compile time, so they are always the ones this app checks
  against.
  """
  use ChroniclesWeb, :controller

  @root Path.expand("../../..", __DIR__)
  @sources %{
    "story-format.md" => "docs/story-format.md",
    "story-schema.json" => "priv/schemas/version.json",
    "SKILL.md" => "docs/story-skill/SKILL.md"
  }

  for {_name, path} <- @sources, do: @external_resource(Path.join(@root, path))
  @files Map.new(@sources, fn {name, path} -> {name, File.read!(Path.join(@root, path))} end)

  def show(conn, %{"file" => "chronicles-story.zip"}) do
    entries =
      for {name, text} <- @files, do: {String.to_charlist("chronicles-story/" <> name), text}

    {:ok, {_name, zip}} = :zip.create(~c"chronicles-story.zip", entries, [:memory])
    send_download(conn, {:binary, zip}, filename: "chronicles-story.zip")
  end

  def show(conn, %{"file" => name}) when name in ["story-format.md", "story-schema.json"] do
    send_download(conn, {:binary, @files[name]}, filename: name)
  end

  def show(conn, _params), do: conn |> put_status(:not_found) |> text("Not found")
end
