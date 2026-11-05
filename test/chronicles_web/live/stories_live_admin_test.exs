defmodule ChroniclesWeb.StoriesLiveAdminTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Repo}

  test "an admin lists other authors' private stories only with 'All stories'", %{conn: conn} do
    secret = story_fixture(user_scope_fixture(), "the-number")
    admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/stories")
    refute has_element?(view, "#stories-#{secret.id}")

    view |> element("#show-all") |> render_click()
    assert_patch(view, ~p"/stories?#{[tags: [], all: true]}")
    assert has_element?(view, "#stories-#{secret.id}")

    {:ok, _view, _html} = live(conn, ~p"/stories/#{secret.slug}")
  end

  test "players and authors get no such filter", %{conn: conn} do
    {:ok, view, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/stories")
    refute has_element?(view, "#list-filter")
  end
end
