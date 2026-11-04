defmodule Jairojobs.Accounts.ScopeTest do
  use Jairojobs.DataCase, async: true

  import Jairojobs.AccountsFixtures

  alias Jairojobs.Accounts.Scope

  describe "role/1 and admin?/1" do
    test "REQ-001-9: role available in scope for a candidate" do
      scope = user_fixture(role: "candidate") |> user_scope_fixture()

      assert scope.user.role == :candidate
      assert Scope.role(scope) == :candidate
      refute Scope.admin?(scope)
    end

    test "REQ-001-9: role available in scope for an employer" do
      scope = user_fixture(role: "employer") |> user_scope_fixture()

      assert Scope.role(scope) == :employer
      refute Scope.admin?(scope)
    end

    test "REQ-001-9: admin? is true only for the admin role" do
      user = %{user_fixture() | role: :admin}
      assert Scope.admin?(Scope.for_user(user))
    end

    test "REQ-001-11: the system scope has no user and is not a web admin" do
      scope = Scope.system()
      assert scope.system
      assert is_nil(scope.user)
      assert Scope.role(scope) == nil
      refute Scope.admin?(scope)
      refute Scope.system?(Scope.for_user(user_fixture()))
      refute Scope.system?(nil)
    end

    test "REQ-001-9: a visitor scope has no role and is not admin" do
      assert Scope.role(nil) == nil
      refute Scope.admin?(nil)
      assert Scope.role(%Scope{user: nil}) == nil
      refute Scope.admin?(%Scope{user: nil})
    end
  end
end
