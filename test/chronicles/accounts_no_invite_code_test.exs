defmodule Chronicles.AccountsNoInviteCodeTest do
  # Not async: it changes the app config, which every signup reads.
  use Chronicles.DataCase, async: false

  import Chronicles.AccountsFixtures

  test "without a configured code, nobody signs up" do
    Application.delete_env(:chronicles, :invite_code)
    on_exit(fn -> Application.put_env(:chronicles, :invite_code, "test-invite") end)

    assert {:error, _changeset} = Chronicles.Accounts.register_user(valid_user_attributes())
  end
end
