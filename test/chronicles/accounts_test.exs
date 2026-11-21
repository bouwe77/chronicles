defmodule Chronicles.AccountsTest do
  use Chronicles.DataCase

  alias Chronicles.Accounts

  import Chronicles.AccountsFixtures
  alias Chronicles.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "create_user/2" do
    setup do
      admin = user_fixture(role: :admin)
      %{scope: user_scope_fixture(admin)}
    end

    test "requires email to be set", %{scope: scope} do
      {:error, changeset} = Accounts.create_user(scope, %{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given", %{scope: scope} do
      {:error, changeset} = Accounts.create_user(scope, %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security", %{scope: scope} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.create_user(scope, %{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{scope: scope} do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.create_user(scope, %{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.create_user(scope, %{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "creates an unconfirmed user", %{scope: scope} do
      email = unique_user_email()
      {:ok, user} = Accounts.create_user(scope, valid_user_attributes(email: email))
      assert user.email == email
      assert is_nil(user.confirmed_at)
    end

    test "only an admin may" do
      assert {:error, :unauthorized} =
               Accounts.create_user(user_scope_fixture(), valid_user_attributes())
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = unconfirmed_user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "get_user_by_magic_link_token/1" do
    setup do
      user = user_fixture()
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      %{user: user, token: encoded_token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_magic_link_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_magic_link_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_magic_link_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "a login link works for 15 minutes" do
      user = user_fixture()
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)
      offset_user_token(hashed_token, -16, :minute)

      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "an invite link (unconfirmed user) works for 2 days" do
      user = unconfirmed_user_fixture()
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      offset_user_token(hashed_token, -3, :day)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)

      offset_user_token(hashed_token, -1, :day)

      assert {:ok, {%User{confirmed_at: %DateTime{}}, _tokens}} =
               Accounts.login_user_by_magic_link(encoded_token)
    end

    test "confirms user and expires tokens" do
      user = unconfirmed_user_fixture()
      refute user.confirmed_at
      {encoded_token, hashed_token} = generate_user_magic_link_token(user)

      assert {:ok, {user, [%{token: ^hashed_token}]}} =
               Accounts.login_user_by_magic_link(encoded_token)

      assert user.confirmed_at
    end

    test "returns user and (deleted) token for confirmed user" do
      user = user_fixture()
      assert user.confirmed_at
      {encoded_token, _hashed_token} = generate_user_magic_link_token(user)
      assert {:ok, {^user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: unconfirmed_user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "update_user_api_access/3" do
    test "only an admin may turn it on, also for themselves" do
      admin = user_fixture() |> User.role_changeset(%{role: :admin}) |> Repo.update!()
      admin_scope = user_scope_fixture(admin)
      user = user_fixture()

      assert {:error, :unauthorized} =
               Accounts.update_user_api_access(user_scope_fixture(user), user, true)

      assert {:ok, %User{api_access: true}} =
               Accounts.update_user_api_access(admin_scope, user, true)

      assert {:ok, %User{api_access: true}} =
               Accounts.update_user_api_access(admin_scope, admin, true)
    end

    test "turning it off revokes the token" do
      admin_scope =
        user_fixture()
        |> User.role_changeset(%{role: :admin})
        |> Repo.update!()
        |> user_scope_fixture()

      {user, token} = api_token_fixture()

      {:ok, user} = Accounts.update_user_api_access(admin_scope, user, false)
      refute Accounts.api_token?(user)

      {:ok, _user} = Accounts.update_user_api_access(admin_scope, user, true)
      refute Accounts.get_user_by_api_token(token)
    end
  end

  describe "API tokens" do
    test "a new user has no API access" do
      user = user_fixture()
      refute user.api_access
      assert {:error, :unauthorized} = Accounts.create_api_token(user)
    end

    test "a token finds its user until it is revoked" do
      {%{id: id} = user, token} = api_token_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_api_token(token)

      :ok = Accounts.delete_api_token(user)
      refute Accounts.get_user_by_api_token(token)
    end

    test "a new token replaces the old one" do
      {user, old_token} = api_token_fixture()
      {:ok, new_token} = Accounts.create_api_token(user)

      refute Accounts.get_user_by_api_token(old_token)
      assert Accounts.get_user_by_api_token(new_token)
    end

    test "a token stops working when the user loses API access" do
      {user, token} = api_token_fixture()
      Repo.update!(Ecto.Changeset.change(user, api_access: false))
      refute Accounts.get_user_by_api_token(token)
    end

    test "an unknown or malformed token finds nobody" do
      refute Accounts.get_user_by_api_token("not base64!")
      refute Accounts.get_user_by_api_token(Base.url_encode64("unknown", padding: false))
    end
  end
end
