defmodule Jairojobs.ReleaseTest do
  use Jairojobs.DataCase, async: false

  import ExUnit.CaptureIO
  import Jairojobs.AccountsFixtures

  alias Jairojobs.Accounts
  alias Jairojobs.Regions
  alias Jairojobs.Release

  test "REQ-001-10: promote a user" do
    user = user_fixture(role: "employer")

    output = capture_io(fn -> Release.promote_admin(user.email) end)

    assert output =~ "#{user.email} is now an admin"
    assert Accounts.get_user!(user.id).role == :admin
  end

  test "REQ-001-10: demote an admin back to the previous role" do
    user = user_fixture(role: "employer")
    _other_admin = user_fixture() |> then(&Release.admin("promote", &1.email))
    {:ok, _} = Release.admin("promote", user.email)

    output = capture_io(fn -> Release.demote_admin(user.email) end)

    assert output =~ "is no longer an admin (now employer)"
    assert Accounts.get_user!(user.id).role == :employer
  end

  test "REQ-001-10: unknown email fails with a clear message" do
    assert Release.admin("promote", "nobody@example.com") ==
             {:error, "No account found for nobody@example.com"}
  end

  test "REQ-002-5: seeding the launch regions in production is safe to run again" do
    assert :ok = Release.seed_regions()
    count = length(Regions.list_regions())
    assert :ok = Release.seed_regions()
    assert length(Regions.list_regions()) == count
    assert count >= 3
  end
end
