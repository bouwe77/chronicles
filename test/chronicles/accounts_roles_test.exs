defmodule Chronicles.AccountsRolesTest do
  use Chronicles.DataCase, async: true

  import Chronicles.AccountsFixtures
  import Chronicles.StoriesFixtures

  alias Chronicles.{Accounts, Games, Repo}
  alias Chronicles.Accounts.Scope
  alias Chronicles.Stories.Story

  defp admin_scope, do: user_fixture() |> set_role(:admin) |> Scope.for_user()

  defp set_role(user, role),
    do: user |> Accounts.User.role_changeset(%{role: role}) |> Repo.update!()

  test "signing up needs the invite code, and makes an author" do
    assert {:error, changeset} =
             Accounts.register_user(valid_user_attributes(invite_code: "wrong"))

    assert "is not valid" in errors_on(changeset).invite_code
    assert {:ok, user} = Accounts.register_user(valid_user_attributes())
    assert user.role == :author
  end

  test "a username is unique regardless of case" do
    user_fixture(username: "Agnes")
    assert {:error, changeset} = Accounts.register_user(valid_user_attributes(username: "agnes"))
    assert "has already been taken" in errors_on(changeset).username
  end

  test "a username has only letters, digits, - and _" do
    assert {:error, changeset} = Accounts.register_user(valid_user_attributes(username: "a b"))
    assert errors_on(changeset).username != []
  end

  test "an admin changes someone else's role, but not their own" do
    admin = admin_scope()
    user = user_fixture()

    assert {:ok, %{role: :player}} = Accounts.update_user_role(admin, user, "player")
    assert Accounts.update_user_role(admin, admin.user, "player") == {:error, :unauthorized}
  end

  test "only an admin changes roles" do
    author = user_scope_fixture()
    assert Accounts.update_user_role(author, user_fixture(), "admin") == {:error, :unauthorized}
  end

  test "deleting a user deletes their stories and every game of them" do
    author = user_scope_fixture()
    player = user_scope_fixture()
    story = story_fixture(author, "the-number", :public)
    {:ok, game, _} = Games.start_game(player, Chronicles.Stories.get_story!(player, story.slug))

    {:ok, _} = Accounts.delete_user(author.user)

    refute Repo.get(Story, story.id)
    refute Repo.get(Games.Game, game.id)
  end
end
