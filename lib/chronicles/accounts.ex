defmodule Chronicles.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Chronicles.Repo

  alias Chronicles.Accounts.{Scope, User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc "Gets a single user, or nil."
  def get_user(id), do: Repo.get(User, id)

  ## Username

  def change_user_username(user, attrs \\ %{}), do: User.username_changeset(user, attrs)

  def update_user_username(user, attrs) do
    user |> User.username_changeset(attrs) |> Repo.update()
  end

  ## Language

  def change_user_locale(user, attrs \\ %{}), do: User.locale_changeset(user, attrs)

  def update_user_locale(user, attrs) do
    user |> User.locale_changeset(attrs) |> Repo.update()
  end

  ## Roles

  @doc "All users, by email. For admins."
  def list_users(%Scope{user: %User{role: :admin}}) do
    User |> order_by(:email) |> Repo.all()
  end

  @doc """
  Creates a user with a role, without an invite code. Only an admin may. The caller sends
  the login link.
  """
  def create_user(%Scope{user: %User{role: :admin}}, attrs) do
    %User{} |> User.admin_changeset(attrs) |> Repo.insert()
  end

  def create_user(_scope, _attrs), do: {:error, :unauthorized}

  @doc "A changeset for the admin's new-user form."
  def change_new_user(attrs \\ %{}),
    do: User.admin_changeset(%User{}, attrs, validate_unique: false)

  @doc """
  Changes a user's role. Only an admin may, and not their own role, so the last admin
  can't lock themselves out.
  """
  def update_user_role(%Scope{user: %User{role: :admin} = admin}, %User{} = user, role)
      when admin.id != user.id do
    user |> User.role_changeset(%{role: role}) |> Repo.update()
  end

  def update_user_role(_scope, _user, _role), do: {:error, :unauthorized}

  @doc """
  Turns a user's API access on or off. Only an admin may, also for themselves. Turning it
  off also deletes the user's API token, so turning it on again doesn't bring that back.
  """
  def update_user_api_access(%Scope{user: %User{role: :admin}}, %User{} = user, api_access) do
    Repo.transact(fn ->
      with {:ok, user} <-
             user |> User.api_access_changeset(%{api_access: api_access}) |> Repo.update() do
        unless user.api_access, do: delete_api_token(user)
        {:ok, user}
      end
    end)
  end

  def update_user_api_access(_scope, _user, _api_access), do: {:error, :unauthorized}

  ## API token

  @doc """
  Creates the user's API token and returns it. A user has at most one: a new one replaces
  the old one. Only the hash is stored, so this is the only time the token can be shown.
  """
  def create_api_token(%User{api_access: true} = user) do
    {token, user_token} = UserToken.build_api_token(user)

    Repo.transact(fn ->
      delete_api_token(user)
      Repo.insert!(user_token)
      {:ok, token}
    end)
  end

  def create_api_token(_user), do: {:error, :unauthorized}

  @doc "Revokes the user's API token, if they have one."
  def delete_api_token(%User{} = user) do
    Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: "api"]))
    :ok
  end

  @doc "Whether the user has an API token."
  def api_token?(%User{} = user) do
    Repo.exists?(from(UserToken, where: [user_id: ^user.id, context: "api"]))
  end

  @doc "The user of an API token, or nil when the token is unknown or the user has no API access."
  def get_user_by_api_token(token) when is_binary(token) do
    case UserToken.verify_api_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Deletes a user with everything they own: their sagas, their stories (with every game of
  those) and their games. The foreign keys do the cascade. While a story of theirs is in
  another user's saga, nothing is deleted.
  """
  def delete_user(%User{} = user) do
    Repo.transact(fn ->
      # Their own sagas first: the database checks a saga's stories as each cascade
      # runs, so a saga of their own stories would otherwise stop the delete.
      Repo.delete_all(from s in Chronicles.Stories.Saga, where: s.author_id == ^user.id)

      user
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.foreign_key_constraint(:id,
        name: :chapters_story_id_fkey,
        message: "has a story in another user's saga; that saga must change first"
      )
      |> Repo.delete()
    end)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Chronicles.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link. The first time, this confirms the user and expires all
  their other tokens; after that, only the used link expires.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/account/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
