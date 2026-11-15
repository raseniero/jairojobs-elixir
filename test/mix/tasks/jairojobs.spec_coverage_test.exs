defmodule Mix.Tasks.Jairojobs.SpecCoverageTest do
  # Not async: swaps the global Mix shell to capture the task's output.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Jairojobs.SpecCoverage

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    specs = Path.join(tmp, "specs")
    tests = Path.join(tmp, "test")
    File.mkdir_p!(specs)
    File.mkdir_p!(tests)

    %{specs: specs, tests: tests, args: ["--specs-dir", specs, "--tests-dir", tests]}
  end

  defp spec(dir, folder, body) do
    path = Path.join([dir, folder, "spec.md"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  defp test_file(dir, name, names) do
    body = Enum.map_join(names, "\n", &~s(  test "#{&1}" do\n    assert true\n  end\n))
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "defmodule Fake do\n#{body}end\n")
  end

  @regions """
  # 002 — Regions

  ### REQ-002-1: Admin-only regions page

  ```gherkin
  Scenario: Admin sees all regions
    Given I am logged in as an Admin

  Scenario: Non-admin is refused
    Given I am logged in as a Candidate
  ```

  ### REQ-002-2: Add a region

  ```gherkin
  Scenario: Add a region
    Given I am an Admin
  ```
  """

  test "passes when every scenario has a test named after it", ctx do
    spec(ctx.specs, "002-regions", @regions)

    test_file(ctx.tests, "regions_test.exs", [
      "REQ-002-1: admin sees all regions",
      "REQ-002-1: non-admin is refused",
      "REQ-002-2: add a region"
    ])

    assert SpecCoverage.run(ctx.args) == :ok
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "All 3 scenarios"
  end

  test "reports each scenario with no test and fails", ctx do
    spec(ctx.specs, "002-regions", @regions)
    test_file(ctx.tests, "regions_test.exs", ["REQ-002-1: admin sees all regions"])

    assert_raise Mix.Error, ~r/2 of 3 scenarios have no test/, fn ->
      SpecCoverage.run(ctx.args)
    end

    assert_received {:mix_shell, :error, [first]}
    assert_received {:mix_shell, :error, [second]}
    assert first =~ "002  REQ-002-1: Non-admin is refused"
    assert second =~ "002  REQ-002-2: Add a region"
  end

  test "a test name that extends the scenario name counts", ctx do
    spec(ctx.specs, "002-regions", @regions)

    test_file(ctx.tests, "live/regions_test.exs", [
      "REQ-002-1: Admin sees all regions, in alphabetical order",
      "REQ-002-1:   non-admin   is refused and sent home",
      "REQ-002-2: add a region (row appears)"
    ])

    assert SpecCoverage.run(ctx.args) == :ok
  end

  test "the requirement id must match, not only the scenario name", ctx do
    spec(ctx.specs, "002-regions", @regions)

    test_file(ctx.tests, "regions_test.exs", [
      "REQ-002-1: admin sees all regions",
      "REQ-002-1: non-admin is refused",
      "REQ-002-1: add a region",
      "add a region"
    ])

    assert_raise Mix.Error, ~r/1 of 3 scenarios have no test/, fn ->
      SpecCoverage.run(ctx.args)
    end
  end

  test "dropped scenarios and the template are ignored", ctx do
    spec(ctx.specs, "_template", "### REQ-NNN-1: x\n\nScenario: <short name>\n")

    spec(ctx.specs, "001-accounts", """
    ### REQ-001-7: Change password

    Scenario: Change password
    Scenario: Wrong current password (dropped 2026-11-12)
    """)

    test_file(ctx.tests, "accounts_test.exs", ["REQ-001-7: change password"])

    assert SpecCoverage.run(ctx.args) == :ok
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "All 1 scenarios"
  end

  test "only the specs named on the command line are checked", ctx do
    spec(ctx.specs, "002-regions", @regions)
    spec(ctx.specs, "003-listings", "### REQ-003-1: Posting\n\nScenario: Candidate is refused\n")

    test_file(ctx.tests, "listings_test.exs", ["REQ-003-1: candidate is refused"])

    assert SpecCoverage.run(ctx.args ++ ["003"]) == :ok
    assert_raise Mix.Error, fn -> SpecCoverage.run(ctx.args ++ ["002", "003"]) end

    assert_raise Mix.Error, ~r/No spec found for 009/, fn ->
      SpecCoverage.run(ctx.args ++ ["009"])
    end
  end

  test "only *_test.exs files are read, and escaped quotes in test names are handled", ctx do
    spec(ctx.specs, "002-regions", """
    ### REQ-002-1: Page

    Scenario: Admin sees "Regions"
    """)

    test_file(ctx.tests, "support/helper.exs", [~S(REQ-002-1: admin sees \"regions\")])

    assert_raise Mix.Error, fn -> SpecCoverage.run(ctx.args) end

    test_file(ctx.tests, "regions_test.exs", [~S(REQ-002-1: admin sees \"regions\")])
    assert SpecCoverage.run(ctx.args) == :ok
  end
end
