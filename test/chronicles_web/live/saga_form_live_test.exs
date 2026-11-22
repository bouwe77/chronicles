defmodule ChroniclesWeb.SagaFormLiveTest do
  # Creating, editing and deleting sagas in the app.
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.SagaFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.Stories

  setup :register_and_log_in_user

  setup %{user: user} do
    %{scope: user_scope_fixture(user)}
  end

  defp add(view, story),
    do: view |> form("#add-chapter-form", chapter: %{story: story.id}) |> render_submit()

  test "a new saga is made from a title and chapters in order", ctx do
    one = story_fixture(ctx.scope, "the-number")
    two = story_fixture(ctx.scope, "the-number-returns")
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/new")

    view |> form("#saga-form", saga: %{title: "Up and Down"}) |> render_change()
    assert has_element?(view, "#saga-slug", "/sagas/up-and-down")
    assert has_element?(view, "#save-saga[disabled]")

    # In the wrong order, the first chapter needs input: the checks say so.
    add(view, two)
    add(view, one)
    assert has_element?(view, "#saga-errors", "needs input")
    assert has_element?(view, "#save-saga[disabled]")

    view |> element("#up-#{one.id}") |> render_click()
    refute has_element?(view, "#saga-errors")
    assert has_element?(view, "#saga-chapters li:nth-child(1)#chapter-#{one.id}")

    assert {:error, {:live_redirect, %{to: "/sagas/up-and-down"}}} =
             view |> element("#save-saga") |> render_click()

    saga = Stories.get_saga("up-and-down")
    assert Enum.map(saga.chapters, & &1.story.slug) == ["the-number", "the-number-returns"]
  end

  test "between two chapters, each ending shows whether it unlocks the next", ctx do
    one = story_fixture(ctx.scope, "the-number")
    two = story_fixture(ctx.scope, "the-number-returns")
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/new")
    add(view, one)
    add(view, two)

    link = "#handover-#{one.id}"
    assert has_element?(view, link, "How chapter 1 can end")
    assert has_element?(view, link, "spare: 3")
    assert has_element?(view, link, "opens chapter 2")
    assert has_element?(view, link, "chapter 2 stays locked")
    assert has_element?(view, "#{link} a[href='/stories/the-number/edit?part=endings']")
    assert has_element?(view, "#{link} a[href='/stories/the-number-returns/edit?part=story']")
  end

  test "a story that can't be a chapter is offered disabled, with the reason", ctx do
    one = story_fixture(ctx.scope, "the-number")
    story_fixture(ctx.scope, "the-bearer-of-this-letter", :public)
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/new")

    # An empty saga has no visibility yet, so every story can be the first chapter.
    refute has_element?(view, "#add-chapter-form option[disabled]")
    refute has_element?(view, "#saga-errors")

    add(view, one)
    assert has_element?(view, "#add-chapter-form option[disabled]", "public, the saga is private")
  end

  test "the link editor changes both halves of a link, and saves both chapters", ctx do
    %{saga: saga, one: one, two: two} = number_saga_fixture(ctx.scope)
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}/edit")
    view |> element("#edit-link-#{one.id}") |> render_click()

    # A win that hands on 9: chapter 2 only takes 0 to 3.
    view |> form("#link-form", %{"outputs" => %{"0" => ~s({"spare": 9})}}) |> render_change()
    assert has_element?(view, "#link-form li:nth-child(1)", "doesn't open chapter 2")

    view |> element("#generate-input") |> render_click()
    assert has_element?(view, "#link-form", "integer, 0–9, required")
    assert has_element?(view, "#link-form li:nth-child(1)", "opens chapter 2")

    view |> form("#link-form") |> render_submit()
    refute has_element?(view, "#link-form")

    one = Stories.get_story!(ctx.scope, one.slug)
    two = Stories.get_story!(ctx.scope, two.slug)
    assert hd(one.head_version.content["endings"])["output"] == %{"spare" => 9}
    assert two.head_version.content["input"]["schema"]["properties"]["spare"]["maximum"] == 9
  end

  test "the link editor shows JSON that doesn't parse, and can't save then", ctx do
    %{saga: saga, one: one} = number_saga_fixture(ctx.scope)
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}/edit")
    view |> element("#edit-link-#{one.id}") |> render_click()

    view |> form("#link-form", %{"input" => "{nope"}) |> render_change()
    assert has_element?(view, "#link-problems", "not valid JSON")
    assert has_element?(view, "#save-link[disabled]")
  end

  test "write a new chapter: back in the saga editor, added, with its input generated", ctx do
    story_fixture(ctx.scope, "the-number")

    {:ok, _} =
      Stories.save_saga(ctx.scope, "solo", %{"title" => "Solo", "stories" => ["the-number"]})

    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/solo/edit")
    assert has_element?(view, "#write-chapter[href='/stories/new?saga=solo']")

    {:ok, view, _html} = live(ctx.conn, ~p"/stories/new?saga=solo")
    assert has_element?(view, "#new-chapter-of", "chapter 2")

    assert {:error, {:live_redirect, %{to: to}}} =
             view |> form("#new-story-form", story: %{title: "The Way Back"}) |> render_submit()

    assert to == "/sagas/solo/edit?add=the-way-back"

    {:ok, view, _html} = live(ctx.conn, to)
    assert has_element?(view, "#saga-chapters li:nth-child(2)", "The Way Back")
    assert has_element?(view, "#link-form", "integer, 0–3, required")
    refute has_element?(view, "#link-problems")

    # Saving the link gives the new chapter its input; then the saga can be saved.
    view |> form("#link-form") |> render_submit()
    refute has_element?(view, "#saga-errors")
    view |> element("#save-saga") |> render_click()

    assert Enum.map(Stories.get_saga("solo").chapters, & &1.story.slug) == [
             "the-number",
             "the-way-back"
           ]
  end

  test "the author edits a saga, and deletes it from the saga page", ctx do
    %{saga: saga, two: two} = number_saga_fixture(ctx.scope)
    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}")
    assert has_element?(view, "#edit-saga[href='/sagas/#{saga.slug}/edit']")

    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}/edit")
    view |> element("#remove-#{two.id}") |> render_click()
    view |> element("#save-saga") |> render_click()
    assert [%{story: %{slug: "the-number"}}] = Stories.get_saga(saga.slug).chapters

    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}")

    assert {:error, {:live_redirect, %{to: "/stories"}}} =
             view |> element("#delete-saga") |> render_click()

    refute Stories.get_saga(saga.slug)
  end

  test "only the author or an admin edits a saga", ctx do
    other = user_scope_fixture()
    %{saga: saga} = number_saga_fixture(other)

    {:ok, view, _html} = live(ctx.conn, ~p"/sagas/#{saga.slug}")
    refute has_element?(view, "#manage-saga")

    assert {:error, {:live_redirect, %{to: "/sagas/the-number"}}} =
             live(ctx.conn, ~p"/sagas/#{saga.slug}/edit")
  end
end
