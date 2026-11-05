defmodule ChroniclesWeb.StoriesLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  setup :register_and_log_in_user

  setup %{user: user} do
    scope = user_scope_fixture(user)

    %{
      number: story_fixture(scope, "the-number"),
      bearer: story_fixture(scope, "the-bearer-of-this-letter")
    }
  end

  test "a tag filters the list, and clicking it again clears it", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/stories")
    assert has_element?(view, "#stories-#{ctx.number.id}")

    view |> element("#tag-filter a", "escape") |> render_click()
    assert_patch(view, ~p"/stories?#{[tags: ["escape"]]}")
    assert has_element?(view, "#stories-#{ctx.bearer.id}")
    refute has_element?(view, "#stories-#{ctx.number.id}")

    view |> element("#tag-filter a", "escape") |> render_click()
    assert has_element?(view, "#stories-#{ctx.number.id}")
  end
end
