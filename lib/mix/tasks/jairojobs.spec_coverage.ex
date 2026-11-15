defmodule Mix.Tasks.Jairojobs.SpecCoverage do
  @shortdoc "Check that every Gherkin scenario in the specs has a REQ-named test"

  @moduledoc """
  Checks the naming rule in the constitution (§3.2): every Gherkin scenario in
  a spec has at least one test named after it.

      mix jairojobs.spec_coverage            # all specs
      mix jairojobs.spec_coverage 003        # only spec 003
      mix jairojobs.spec_coverage 001 002

  A scenario `Scenario: Add a region` under `### REQ-002-2: …` is covered when
  some test name **starts with** `REQ-002-2: Add a region`, ignoring case and
  repeated spaces — so `test "REQ-002-2: add a region (row appears)"` counts.
  Scenarios marked `(dropped …)` and the `_template` folder are ignored.

  Prints the scenarios with no such test and exits non-zero if there are any.
  It does not run the tests (`mix precommit` does); it only shows that a test
  with the right name exists. Run it by hand when closing a spec.

  Options: `--specs-dir` (default `docs/specs`), `--tests-dir` (default `test`).
  """

  use Mix.Task

  @switches [specs_dir: :string, tests_dir: :string]

  @impl Mix.Task
  def run(args) do
    {opts, numbers} = OptionParser.parse!(args, strict: @switches)
    specs_dir = Keyword.get(opts, :specs_dir, "docs/specs")
    tests_dir = Keyword.get(opts, :tests_dir, "test")

    scenarios = specs_dir |> spec_files(numbers) |> Enum.flat_map(&scenarios/1)
    tests = test_names(tests_dir)

    case Enum.reject(scenarios, &covered?(&1, tests)) do
      [] ->
        Mix.shell().info("All #{length(scenarios)} scenarios have a REQ-named test.")

      missing ->
        for %{spec: spec, req: req, name: name} <- missing do
          Mix.shell().error("#{spec}  #{req}: #{name}")
        end

        Mix.raise(
          "#{length(missing)} of #{length(scenarios)} scenarios have no test named " <>
            "\"REQ-<id>: <scenario name>\" (constitution §3.2)"
        )
    end
  end

  # {spec number, path} for each spec, or only for the numbers asked for.
  defp spec_files(specs_dir, numbers) do
    all =
      for path <- Path.wildcard(Path.join(specs_dir, "*/spec.md")),
          [number] <- [Regex.run(~r/^\d{3}/, path |> Path.dirname() |> Path.basename())],
          do: {number, path}

    case numbers do
      [] ->
        Enum.sort(all)

      numbers ->
        for number <- numbers do
          Enum.find(all, &(elem(&1, 0) == number)) ||
            Mix.raise("No spec found for #{number} in #{specs_dir}")
        end
    end
  end

  # Every `Scenario:` line, with the `### REQ-…:` heading it sits under.
  defp scenarios({number, path}) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {req, found} ->
      cond do
        match = Regex.run(~r/^###\s+(REQ-\d+-\d+):/, line) ->
          {Enum.at(match, 1), found}

        req && String.contains?(line, "(dropped") ->
          {req, found}

        match = req && Regex.run(~r/^\s*Scenario:\s*(.+?)\s*$/, line) ->
          {req, [%{spec: number, req: req, name: Enum.at(match, 1)} | found]}

        true ->
          {req, found}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp test_names(tests_dir) do
    for path <- Path.wildcard(Path.join(tests_dir, "**/*_test.exs")),
        [_, name] <- Regex.scan(~r/^\s*test\s+"((?:[^"\\]|\\.)*)"/m, File.read!(path)),
        do: name |> String.replace(~S(\"), ~S(")) |> normalize()
  end

  defp covered?(%{req: req, name: name}, tests) do
    wanted = normalize("#{req}: #{name}")
    Enum.any?(tests, &String.starts_with?(&1, wanted))
  end

  defp normalize(text) do
    text |> String.downcase() |> String.split() |> Enum.join(" ")
  end
end
