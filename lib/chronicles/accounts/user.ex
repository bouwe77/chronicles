defmodule Chronicles.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    # Shown to other users, for example as a story's author. The email never is.
    field :username, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true
    # A player plays; an author also writes stories; an admin also manages users.
    field :role, Ecto.Enum, values: [:player, :author, :admin], default: :player
    # The language of the app for this user; nil means the browser's language.
    field :locale, :string
    # Whether the user may use the JSON API. Off for everyone until an admin turns it on.
    field :api_access, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc "A changeset for an admin who creates (invites) a user: email, username and role."
  def admin_changeset(user, attrs, opts \\ []) do
    user
    |> email_changeset(attrs, opts)
    |> username_changeset(attrs)
    |> role_changeset(attrs)
  end

  @doc "A changeset for the username: letters, digits, `-` and `_`, unique regardless of case."
  def username_changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_-]+$/,
      message: "can only have letters, digits, - and _"
    )
    |> unique_constraint(:username, name: :users_username_index)
  end

  @doc "The languages of the app."
  def locales, do: ~w(en nl)

  @doc "A changeset for the language: one of `locales/0`, or nil for the browser's language."
  def locale_changeset(user, attrs) do
    user
    |> cast(attrs, [:locale], empty_values: [""])
    |> validate_inclusion(:locale, locales())
  end

  @doc "A changeset for an admin turning API access on or off."
  def api_access_changeset(user, attrs) do
    user
    |> cast(attrs, [:api_access])
    |> validate_required([:api_access])
  end

  @doc "A changeset for an admin changing a user's role."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Chronicles.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end
end
