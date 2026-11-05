defmodule ChroniclesWeb.StoryUploadLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Chronicles.{Accounts, Repo}

  setup :register_and_log_in_user

  defp upload(view, name, content) do
    view
    |> file_input("#upload-form", :story, [
      %{name: name, content: content, type: "application/json"}
    ])
    |> render_upload(name)

    view |> form("#upload-form", %{"slug" => ""}) |> render_change()
  end

  test "a new file makes a story, with the slug from its name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stories/upload")
    upload(view, "my-number.json", Jason.encode!(Chronicles.Play.story("the-number")))

    assert view |> element("#upload-form input[name=slug]") |> render() =~ ~s(value="my-number")

    assert {:error, {:live_redirect, %{to: "/stories/my-number"}}} =
             view |> form("#upload-form", %{"slug" => "my-number"}) |> render_submit()
  end

  test "invalid content lists the errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stories/upload")
    content = Map.put(Chronicles.Play.story("the-number"), "starting_location", "nowhere")
    upload(view, "broken.json", Jason.encode!(content))

    view |> form("#upload-form", %{"slug" => "broken"}) |> render_submit()
    assert has_element?(view, "#upload-errors", ~s(starting_location "nowhere"))
    assert has_element?(view, "#copy-errors[data-from=upload-error-list]")
  end

  test "a file that isn't JSON says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stories/upload")
    upload(view, "broken.json", "not json")

    view |> form("#upload-form", %{"slug" => "broken"}) |> render_submit()
    assert has_element?(view, "#upload-errors", "not a JSON object")
  end

  test "a player can't upload", %{conn: conn, user: user} do
    user |> Accounts.User.role_changeset(%{role: :player}) |> Repo.update!()
    assert {:error, {:live_redirect, %{to: "/stories"}}} = live(conn, ~p"/stories/upload")
  end
end
