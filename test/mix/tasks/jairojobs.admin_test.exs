defmodule Mix.Tasks.Jairojobs.AdminTest do
  use Jairojobs.DataCase, async: false

  import Jairojobs.AccountsFixtures

  alias Jairojobs.Accounts
  alias Mix.Tasks.Jairojobs.Admin

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "promote" do
    test "REQ-001-10: promote a user" do
      user = user_fixture(role: "employer")

      Admin.run(["promote", user.email])

      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ user.email
      assert msg =~ "is now an admin"
      assert Accounts.get_user!(user.id).role == :admin
    end

    test "REQ-001-10: unknown email fails with a clear message" do
      assert_raise Mix.Error, ~r/No account found for nobody@example.com/, fn ->
        Admin.run(["promote", "nobody@example.com"])
      end
    end

    test "REQ-001-10: unconfirmed user cannot be promoted" do
      user = unconfirmed_user_fixture()

      assert_raise Mix.Error, ~r/has not confirmed/, fn ->
        Admin.run(["promote", user.email])
      end

      assert Accounts.get_user!(user.id).role == :candidate
    end
  end

  describe "demote" do
    test "REQ-001-10: demote an admin back to the previous role" do
      _other_admin = admin_fixture()
      admin = admin_fixture(role: "employer")

      Admin.run(["demote", admin.email])

      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ admin.email
      assert msg =~ "employer"
      assert Accounts.get_user!(admin.id).role == :employer
    end

    test "REQ-001-10: unknown email fails with a clear message" do
      assert_raise Mix.Error, ~r/No account found for nobody@example.com/, fn ->
        Admin.run(["demote", "nobody@example.com"])
      end
    end

    test "REQ-001-10: cannot demote the only admin" do
      only_admin = admin_fixture()

      assert_raise Mix.Error, ~r/only admin/, fn ->
        Admin.run(["demote", only_admin.email])
      end

      assert Accounts.get_user!(only_admin.id).role == :admin
    end

    test "REQ-001-10: demoting a non-admin fails with a clear message" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/is not an admin/, fn ->
        Admin.run(["demote", user.email])
      end
    end
  end

  describe "usage" do
    test "REQ-001-10: unknown subcommand or missing email prints usage" do
      assert_raise Mix.Error, ~r/Usage: mix jairojobs.admin/, fn -> Admin.run([]) end
      assert_raise Mix.Error, ~r/Usage: mix jairojobs.admin/, fn -> Admin.run(["promote"]) end

      assert_raise Mix.Error, ~r/Usage: mix jairojobs.admin/, fn ->
        Admin.run(["frobnicate", "a@b.c"])
      end
    end
  end
end
