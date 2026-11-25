defmodule Chronicles.Markdown do
  @moduledoc """
  Markdown in log text (see `plans/markdown-log.md`). CommonMark with all extensions off,
  so tables and strikethrough show as text. Links, images and raw HTML are not supported:
  the validator rejects them on save, and `to_html/1` never renders raw HTML.
  """

  # One newline is a line break: what the author types is what the player sees.
  @options [render: [hardbreaks: true]]

  @unsupported %{
    MDEx.Link => "links",
    MDEx.Image => "images",
    MDEx.HtmlBlock => "raw HTML",
    MDEx.HtmlInline => "raw HTML"
  }

  @doc "What the text uses that log text doesn't support, such as `[\"links\"]`, once each."
  def unsupported(text) do
    text
    |> MDEx.parse_document!(@options)
    |> Enum.flat_map(&List.wrap(@unsupported[&1.__struct__]))
    |> Enum.uniq()
  end

  @doc """
  The text as HTML. Every heading becomes an `h4`, one level below the location heading
  in the log. Raw HTML is left out, also in text saved before the save check existed.
  """
  def to_html(text) do
    text
    |> MDEx.parse_document!(@options)
    |> MDEx.traverse_and_update(fn
      %MDEx.Heading{} = heading -> %{heading | level: 4}
      node -> node
    end)
    |> MDEx.to_html!(@options)
  end
end
