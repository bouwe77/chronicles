defmodule ChroniclesWeb.UserLive.Account do
  use ChroniclesWeb, :live_view

  on_mount {ChroniclesWeb.UserAuth, :require_sudo_mode}

  alias Chronicles.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-semibold tracking-tight">{gettext("Account")}</h1>

      <.form for={@username_form} id="username_form" phx-submit="update_username">
        <.input
          field={@username_form[:username]}
          type="text"
          label={gettext("Username (shown to other players)")}
          autocomplete="nickname"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with={gettext("Saving...")}>{gettext("Change username")}</.button>
      </.form>

      <div class="divider" />

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label={gettext("Email")}
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with={gettext("Changing...")}>{gettext("Change email")}</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label={gettext("New password")}
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label={gettext("Confirm new password")}
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with={gettext("Saving...")}>
          {gettext("Save password")}
        </.button>
      </.form>

      <div class="divider" />

      <section id="delete-account" class="space-y-3">
        <h2 class="font-semibold">{gettext("Delete account")}</h2>
        <p class="text-sm text-base-content/70">
          {gettext(
            "This deletes your account, your stories with every game of them, and your games. It can't be undone."
          )}
        </p>
        <.button
          id="delete-account-button"
          phx-click="delete_account"
          data-confirm={gettext("Delete your account and everything you own?")}
          class="border-error text-error hover:border-error hover:text-error"
        >
          {gettext("Delete my account")}
        </.button>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, gettext("Your email address is changed."))

        {:error, _} ->
          put_flash(socket, :error, gettext("This link is not valid or has expired."))
      end

    {:ok, push_navigate(socket, to: ~p"/account")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:username_form, to_form(Accounts.change_user_username(user)))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/account/confirm-email/#{&1}")
        )

        info = gettext("We sent a link to the new address. Open it to confirm the change.")
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("update_username", %{"user" => user_params}, socket) do
    case Accounts.update_user_username(socket.assigns.current_scope.user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:username_form, to_form(Accounts.change_user_username(user)))
         |> put_flash(
           :info,
           gettext("Your username is now %{username}.", username: user.username)
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :username_form, to_form(changeset, action: :update))}
    end
  end

  def handle_event("delete_account", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.delete_user(user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Your account is deleted."))
         |> redirect(to: ~p"/")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("A story of yours is in another user's series. Ask them to remove it first.")
         )}
    end
  end
end
