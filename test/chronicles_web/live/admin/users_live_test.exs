defmodule ChroniclesWeb.Admin.UsersLiveTest do
  use ChroniclesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures

  alias Chronicles.{Accounts, Repo}

  test "a non-admin is sent away", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/stories"}}} = live(conn, ~p"/admin/users")
  end

  test "an admin changes a role, but has no picker for their own", %{conn: conn} do
    admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
    other = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    refute has_element?(view, "#role-form-#{admin.id}")

    view
    |> element("#role-form-#{other.id}")
    |> render_change(%{"user_id" => other.id, "role" => "player"})

    assert Accounts.get_user!(other.id).role == :player
  end

  test "an admin creates a user, who gets a login link", %{conn: conn} do
    admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    view
    |> form("#new-user-form", user: %{email: "new@example.com", username: "taken"})
    |> render_change()

    view
    |> form("#new-user-form",
      user: %{email: "new@example.com", username: "newbie", role: "author"}
    )
    |> render_submit()

    user = Accounts.get_user_by_email("new@example.com")
    assert %{username: "newbie", role: :author} = user
    assert has_element?(view, "#users-#{user.id}")
    assert Repo.get_by(Accounts.UserToken, user_id: user.id, context: "login")
  end

  test "a new user needs a valid email and username", %{conn: conn} do
    admin = user_fixture() |> Accounts.User.role_changeset(%{role: :admin}) |> Repo.update!()
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/users")

    view
    |> form("#new-user-form", user: %{email: "nope", username: "x"})
    |> render_submit()

    assert has_element?(view, "#new-user-form", "must have the @ sign and no spaces")
    assert Accounts.get_user_by_email("nope") == nil
  end

  test "only admins create users" do
    assert Accounts.create_user(user_scope_fixture(), %{}) == {:error, :unauthorized}
  end
end
