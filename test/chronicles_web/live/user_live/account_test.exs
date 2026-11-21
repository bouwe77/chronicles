defmodule ChroniclesWeb.UserLive.AccountTest do
  use ChroniclesWeb.ConnCase, async: true

  alias Chronicles.Accounts
  import Phoenix.LiveViewTest
  import Chronicles.AccountsFixtures

  describe "Account page" do
    test "renders account page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/account")

      assert html =~ "Change email"
      refute html =~ "password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/account")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/account")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "Log in again to open this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/account")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "We sent a link to the new address"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/account")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/account")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change email"
      assert result =~ "did not change"
    end
  end

  describe "delete account" do
    test "deletes the user and leaves the page", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/account")

      assert {:error, {:redirect, %{to: "/"}}} =
               view |> element("#delete-account-button") |> render_click()

      refute Chronicles.Accounts.get_user_by_email(user.email)
    end
  end

  describe "API token" do
    test "is hidden without API access", %{conn: conn} do
      {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/account")
      refute has_element?(lv, "#api-token")
    end

    test "is created once, shown once, and revoked", %{conn: conn} do
      user =
        user_fixture() |> Ecto.Changeset.change(api_access: true) |> Chronicles.Repo.update!()

      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/account")

      refute has_element?(lv, "#revoke-api-token")
      lv |> element("#create-api-token") |> render_click()

      token =
        lv
        |> element("#api-token-value")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()

      assert Accounts.get_user_by_api_token(String.trim(token))

      lv |> element("#revoke-api-token") |> render_click()
      refute has_element?(lv, "#api-token-value")
      refute Accounts.get_user_by_api_token(String.trim(token))
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/account/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/account"
      assert %{"info" => message} = flash
      assert message == "Your email address is changed."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/account/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/account"
      assert %{"error" => message} = flash
      assert message == "This link is not valid or has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/account/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/account"
      assert %{"error" => message} = flash
      assert message == "This link is not valid or has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/account/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
