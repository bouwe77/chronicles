defmodule ChroniclesWeb.NewStoryLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Repo, Stories}

  setup :register_and_log_in_user

  test "the example sketch makes a story with the title's slug", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/stories/new")
    assert has_element?(view, "#sketch-summary", "6 locations")

    view |> form("#new-story-form", story: %{title: "The Old House"}) |> render_change()
    assert has_element?(view, "#story-slug", "/stories/the-old-house")

    assert {:error, {:live_redirect, %{to: "/stories/the-old-house"}}} =
             view |> form("#new-story-form", story: %{title: "The Old House"}) |> render_submit()

    story = Stories.get_story!(user_scope_fixture(user), "the-old-house")
    assert story.head_version.content["starting_location"] == "front_door"
  end

  test "sketch mistakes are listed and block creating", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stories/new")

    view
    |> form("#new-story-form", story: %{title: "Broken", sketch: "- a\n  - exit: b\n"})
    |> render_change()

    assert has_element?(view, "#sketch-errors", ~s(line 2: there is no location "b"))
    assert has_element?(view, "#create-story[disabled]")
  end

  test "a taken slug is shown, and nothing is replaced", %{conn: conn} do
    story_fixture(user_scope_fixture(), "the-number")
    {:ok, view, _html} = live(conn, ~p"/stories/new")

    view |> form("#new-story-form", story: %{title: "The Number"}) |> render_submit()
    assert has_element?(view, "#story-slug", "is already taken")
  end

  test "a player can't write stories", %{conn: conn, user: user} do
    user |> Accounts.User.role_changeset(%{role: :player}) |> Repo.update!()
    assert {:error, {:live_redirect, %{to: "/stories"}}} = live(conn, ~p"/stories/new")
  end
end
