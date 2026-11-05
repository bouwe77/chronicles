defmodule ChroniclesWeb.EditStoryLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.Stories

  setup :register_and_log_in_user

  setup %{user: user} do
    scope = user_scope_fixture(user)
    %{scope: scope, story: story_fixture(scope, "the-number")}
  end

  defp edit_text(view, text),
    do: view |> form("#part-form", %{"text" => text}) |> render_change()

  defp select(view, part),
    do: view |> element(~s(#parts button[phx-value-part="#{part}"])) |> render_click()

  test "an edit is checked as you type, and saving makes a new head", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")
    assert has_element?(view, "#save[disabled]")

    story = Stories.Authoring.fragment(ctx.story.head_version.content, :story)
    edit_text(view, Jason.encode!(Map.put(story, "story_title", "The Number, edited")))
    assert has_element?(view, "#unsaved")
    assert has_element?(view, "#problems", "No problems found.")

    view |> element("#save") |> render_click()
    assert Stories.title(Stories.get_story!(ctx.scope, ctx.story.slug)) == "The Number, edited"
    refute has_element?(view, "#unsaved")
  end

  test "unsaved work survives a reload, until it is saved or discarded", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")
    story = Stories.Authoring.fragment(ctx.story.head_version.content, :story)
    edit_text(view, Jason.encode!(Map.put(story, "story_title", "Draft title")))

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")
    assert has_element?(view, "h1", "Draft title")
    assert has_element?(view, "#unsaved")

    view |> element("#discard") |> render_click()
    assert has_element?(view, "h1", "The Number")
    refute has_element?(view, "#unsaved")
    assert Stories.get_story!(ctx.scope, ctx.story.slug).draft == nil

    edit_text(view, Jason.encode!(Map.put(story, "story_title", "Draft title")))
    view |> element("#save") |> render_click()
    assert Stories.get_story!(ctx.scope, ctx.story.slug).draft == nil
  end

  test "undoing every change clears the draft", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")
    story = Stories.Authoring.fragment(ctx.story.head_version.content, :story)

    edit_text(view, Jason.encode!(Map.put(story, "story_title", "Draft title")))
    assert Stories.get_story!(ctx.scope, ctx.story.slug).draft
    edit_text(view, Jason.encode!(story))
    assert Stories.get_story!(ctx.scope, ctx.story.slug).draft == nil
  end

  test "invalid JSON and content problems are shown, and block saving", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")

    edit_text(view, "{ not json")
    assert has_element?(view, "#json-error")

    select(view, "location:zero")
    edit_text(view, ~s({"name": "Zero", "description": "", "exits": {"on": {"to": "nowhere"}}}))
    assert has_element?(view, "#problems", ~s(points to unknown location "nowhere"))
    assert has_element?(view, "#save[disabled]")
  end

  test "add, rename and remove a location, with the room badges", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")

    view |> form("#add-location", %{"kind" => "location", "new_id" => "attic"}) |> render_submit()
    assert has_element?(view, ~s(#parts button[phx-value-part="location:attic"]), "unreachable")

    view |> form("#rename-form", %{"to" => "loft"}) |> render_submit()
    assert has_element?(view, ~s(#parts button[phx-value-part="location:loft"]))

    view |> element("#remove-part") |> render_click()
    refute has_element?(view, ~s(#parts button[phx-value-part="location:loft"]))
  end

  test "find uses lists where an id appears", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories/#{ctx.story.slug}/edit")
    view |> form("#find-form", %{"find" => "/moves"}) |> render_change()
    assert has_element?(view, "#uses", "/endings/")
  end

  test "only the author edits", ctx do
    other = log_in_user(build_conn(), user_fixture())
    story = story_fixture(user_scope_fixture(), "the-bearer-of-this-letter", :public)

    assert {:error, {:live_redirect, %{to: "/stories/the-bearer-of-this-letter"}}} =
             live(other, ~p"/stories/#{story.slug}/edit")

    assert {:error, {:live_redirect, _}} = live(ctx.conn, ~p"/stories/#{story.slug}/edit")
  end
end
