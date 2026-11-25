defmodule Chronicles.MarkdownTest do
  use ExUnit.Case, async: true

  alias Chronicles.Markdown

  test "the supported syntax passes the check" do
    text = "# Title\n\nA *b* **c** `d`\n\n- one\n1. two\n\n> quote\n\n---\n\n| a | ~~b~~"
    assert Markdown.unsupported(text) == []
  end

  test "links, autolinks, images and raw HTML are found, once per kind" do
    assert Markdown.unsupported("[a](https://x) <https://y>") == ["links"]
    assert Markdown.unsupported("![a](b.png)") == ["images"]
    assert Markdown.unsupported("<div>a</div>\n\nb <b>c</b>") == ["raw HTML"]
  end

  test "one newline is a line break, every heading is an h4, raw HTML is left out" do
    assert Markdown.to_html("a\nb") =~ "a<br />"
    assert Markdown.to_html("# Big") =~ "<h4>Big</h4>"
    refute Markdown.to_html("<script>alert(1)</script>") =~ "<script"
  end
end
