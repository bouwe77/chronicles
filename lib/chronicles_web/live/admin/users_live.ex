defmodule ChroniclesWeb.Admin.UsersLive do
  @moduledoc """
  Admins only: every user, with a role picker, and a form that creates a user and emails
  them a login link. Your own role can't be changed here.
  """
  use ChroniclesWeb, :live_view

  alias Chronicles.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Users"))
     |> assign(:form, to_form(Accounts.change_new_user()))
     |> stream(:users, Accounts.list_users(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_new_user(params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    case Accounts.create_user(socket.assigns.current_scope, params) do
      {:ok, user} ->
        {:ok, _} = Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))

        {:noreply,
         socket
         |> stream_insert(:users, user)
         |> assign(form: to_form(Accounts.change_new_user()))
         |> put_flash(
           :info,
           gettext("%{email} can log in with the link we sent.", email: user.email)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Only admins can create users."))}
    end
  end

  def handle_event("set_role", %{"user_id" => id, "role" => role}, socket) do
    scope = socket.assigns.current_scope
    user = Accounts.get_user!(id)

    case Accounts.update_user_role(scope, user, role) do
      {:ok, user} ->
        {:noreply,
         socket
         |> stream_insert(:users, user)
         |> put_flash(:info, gettext("%{email} is now %{role}.", email: user.email, role: role))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not change the role."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-semibold tracking-tight">{gettext("Users")}</h1>
      <p class="text-sm text-base-content/70">
        {gettext("A player plays stories. An author also writes them. An admin also manages users.")}
      </p>

      <ul
        id="users"
        phx-update="stream"
        class="divide-y divide-base-300 rounded-2xl border border-base-300"
      >
        <li
          :for={{id, user} <- @streams.users}
          id={id}
          class="flex items-center justify-between gap-4 px-4 py-3"
        >
          <span class="truncate">{user.email}</span>
          <%= if user.id == @current_scope.user.id do %>
            <span class="text-sm text-base-content/60">{role_label(user.role)} ({gettext("you")})</span>
          <% else %>
            <.form for={to_form(%{})} id={"role-form-#{user.id}"} phx-change="set_role">
              <input type="hidden" name="user_id" value={user.id} />
              <.input
                type="select"
                name="role"
                value={user.role}
                options={for role <- [:player, :author, :admin], do: {role_label(role), role}}
                aria-label={gettext("Role of %{email}", email: user.email)}
              />
            </.form>
          <% end %>
        </li>
      </ul>

      <section class="space-y-3 rounded-2xl border border-base-300 p-4">
        <h2 class="font-semibold">{gettext("New user")}</h2>
        <.form
          for={@form}
          id="new-user-form"
          phx-change="validate"
          phx-submit="create"
          class="grid gap-x-3 sm:grid-cols-[1fr_1fr_10rem_auto] sm:items-end"
        >
          <.input field={@form[:email]} type="email" label={gettext("Email")} required />
          <.input field={@form[:username]} type="text" label={gettext("Username")} required />
          <.input
            field={@form[:role]}
            type="select"
            label={gettext("Role")}
            options={for role <- [:player, :author, :admin], do: {role_label(role), role}}
          />
          <.button
            id="create-user"
            variant="primary"
            class="mb-2"
            phx-disable-with={gettext("Creating...")}
          >
            {gettext("Create")}
          </.button>
        </.form>
        <p class="text-sm text-base-content/60">
          {gettext("They get an email with a link to log in. No password needed.")}
        </p>
      </section>
    </Layouts.app>
    """
  end

  defp role_label(:player), do: gettext("Player")
  defp role_label(:author), do: gettext("Author")
  defp role_label(:admin), do: gettext("Admin")
end
