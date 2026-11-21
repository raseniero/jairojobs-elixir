defmodule Mix.Tasks.Jairojobs.SpecReviewTest do
  # Not async: swaps the global Mix shell to capture the task's output.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Jairojobs.SpecReview

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    specs = Path.join(tmp, "specs")
    File.mkdir_p!(specs)
    git(tmp, ["init", "-q"])

    %{root: tmp, specs: specs, args: ["--specs-dir", specs, "007"]}
  end

  defp git(dir, args) do
    {out, 0} =
      System.cmd(
        "git",
        ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@example.com"] ++ args,
        stderr_to_stdout: true
      )

    String.trim(out)
  end

  defp commit(root, message) do
    git(root, ["add", "-A"])
    git(root, ["commit", "-q", "-m", message])
    git(root, ["rev-parse", "--short", "HEAD"])
  end

  defp write(specs, relative, body) do
    path = Path.join(specs, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  defp review(sha) do
    """
    ## Review before approval

    **Reviewed:** 2026-11-20 at commit `#{sha}`

    | Checked against | Result |
    |---|---|
    | This spec's diagrams, scenario by scenario | agrees |
    | Architecture overview, data model and ERD | agrees |
    | C4 and use case diagrams | agrees |
    | Earlier specs this one changes | agrees |
    | Not checked | nothing left out |
    """
  end

  # A small spec that passes every check once its review section names a commit.
  defp spec(opts \\ []) do
    """
    # 007 — Applications

    **Status:** #{Keyword.get(opts, :status, "Draft")}

    ## User stories

    **US-007-1**
    - As a Candidate,
    - I want to apply,
    - so that I am considered.

    **US-007-2**
    - As an Employer,
    - I want an email,
    - so that I know.

    ## Screen flow

    ![Screen flow](diagrams/screenflow-apply.svg)

    | Story | Path through the screen flow |
    |---|---|
    | US-007-1 apply | Listing → Apply |
    #{Keyword.get(opts, :screen_row, "| US-007-2 told | Email |")}

    ## Flows (activity diagrams)

    | Flow | Covers | Diagram |
    |---|---|---|
    | Apply | #{Keyword.get(opts, :covers, "REQ-007-1, -2")} | [activity-apply](diagrams/activity-apply.svg) |

    ## Requirements

    ### REQ-007-1: Apply to a listing

    **Serves:** US-007-1

    #{Keyword.get(opts, :narrative, "Only a Published listing can be applied to (REQ-005-1).")}

    ```gherkin
    Scenario: Apply
      Given a Published listing
    #{Keyword.get(opts, :extra_scenario, "")}
    ```

    ### REQ-007-2: The employer is emailed

    **Serves:** #{Keyword.get(opts, :serves_2, "US-007-2")}

    ```gherkin
    Scenario: Email
      Given an application
    ```

    ## Open questions

    #{Keyword.get(opts, :open, "- None.")}

    #{Keyword.get(opts, :review, "")}
    ## Traceability

    | Story | Requirements |
    |---|---|
    | US-007-1 | REQ-007-1 |
    | US-007-2 | REQ-007-2 |

    ## Changelog

    | Date | Change |
    |---|---|
    | 2026-11-20 | Created |
    #{Keyword.get(opts, :changelog, "")}
    """
  end

  # Spec 005 exists so that the reference REQ-005-1 resolves.
  defp other_spec(specs) do
    write(specs, "005-public/spec.md", "# 005\n\n### REQ-005-1: Only Published is public\n")
  end

  defp diagrams(specs) do
    for name <- ~w(screenflow-apply activity-apply) do
      write(specs, "007-applications/diagrams/#{name}.puml", "@startuml #{name}\n@enduml\n")
      write(specs, "007-applications/diagrams/#{name}.svg", "<svg/>\n")
    end
  end

  # Commits a reviewable spec, then records the review of that commit.
  defp reviewed(ctx, opts \\ []) do
    other_spec(ctx.specs)
    diagrams(ctx.specs)
    write(ctx.specs, "007-applications/spec.md", spec(opts))
    sha = commit(ctx.root, "draft")
    write(ctx.specs, "007-applications/spec.md", spec([review: review(sha)] ++ opts))
    sha
  end

  defp problems do
    receive do
      {:mix_shell, :error, [line]} -> [line | problems()]
    after
      0 -> []
    end
  end

  defp assert_fails(ctx, expected) do
    assert_raise Mix.Error, fn -> SpecReview.run(ctx.args) end
    found = problems()

    assert Enum.any?(found, &(&1 =~ expected)),
           "expected #{inspect(expected)} in #{inspect(found)}"
  end

  test "passes when the spec is consistent and reviewed at its current content", ctx do
    sha = reviewed(ctx)

    assert SpecReview.run(ctx.args) == :ok
    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "007"
    assert msg =~ sha
  end

  test "still passes after the review, the changelog and the status change", ctx do
    sha = reviewed(ctx)

    write(
      ctx.specs,
      "007-applications/spec.md",
      spec(
        review: review(sha),
        status: "Approved",
        changelog: "| 2026-11-21 | Approved |"
      )
    )

    assert SpecReview.run(ctx.args) == :ok
  end

  test "fails when there is no review section", ctx do
    other_spec(ctx.specs)
    diagrams(ctx.specs)
    write(ctx.specs, "007-applications/spec.md", spec())
    commit(ctx.root, "draft")

    assert_fails(ctx, "Review before approval")
  end

  test "fails when a row of the review has no result", ctx do
    sha = reviewed(ctx)

    emptied =
      String.replace(
        review(sha),
        "| C4 and use case diagrams | agrees |",
        "| C4 and use case diagrams | |"
      )

    write(ctx.specs, "007-applications/spec.md", spec(review: emptied))

    assert_fails(ctx, "C4 and use case diagrams")
  end

  test "fails when the spec changed after the reviewed commit", ctx do
    sha = reviewed(ctx)

    write(
      ctx.specs,
      "007-applications/spec.md",
      spec(review: review(sha), narrative: "Any listing can be applied to (REQ-005-1).")
    )

    assert_fails(ctx, "changed since")
  end

  test "fails when a diagram changed after the reviewed commit", ctx do
    reviewed(ctx)

    write(
      ctx.specs,
      "007-applications/diagrams/activity-apply.puml",
      "@startuml x\n:new;\n@enduml\n"
    )

    write(ctx.specs, "007-applications/diagrams/activity-apply.svg", "<svg>new</svg>\n")

    assert_fails(ctx, "changed since")
  end

  test "fails when the reviewed commit does not exist", ctx do
    reviewed(ctx)
    write(ctx.specs, "007-applications/spec.md", spec(review: review("0000000")))

    assert_fails(ctx, "0000000")
  end

  test "fails when a requirement is in no row of the Flows table", ctx do
    reviewed(ctx, covers: "REQ-007-1")

    assert_fails(ctx, "REQ-007-2 is in 0 rows of the Flows table")
  end

  test "fails when a story has no row in the screen-flow table", ctx do
    reviewed(ctx, screen_row: "")

    assert_fails(ctx, "US-007-2 has no row in the screen-flow table")
  end

  test "fails when a Serves line and the traceability table disagree", ctx do
    reviewed(ctx, serves_2: "US-007-1, US-007-2")

    assert_fails(ctx, "REQ-007-2 serves US-007-1")
  end

  test "fails when a reference points at a requirement that does not exist", ctx do
    reviewed(ctx, narrative: "Only a Published listing can be applied to (REQ-005-9).")

    assert_fails(ctx, "REQ-005-9")
  end

  test "fails when a named diagram is missing", ctx do
    reviewed(ctx)
    File.rm!(Path.join(ctx.specs, "007-applications/diagrams/activity-apply.svg"))

    assert_fails(ctx, "activity-apply.svg")
  end

  test "fails when a diagram's source is newer than its image", ctx do
    other_spec(ctx.specs)
    diagrams(ctx.specs)
    write(ctx.specs, "007-applications/spec.md", spec())
    commit(ctx.root, "draft")

    write(
      ctx.specs,
      "007-applications/diagrams/activity-apply.puml",
      "@startuml x\n:new;\n@enduml\n"
    )

    sha = commit(ctx.root, "source only")
    write(ctx.specs, "007-applications/spec.md", spec(review: review(sha)))

    assert_fails(ctx, "activity-apply.svg is older than its source")
  end

  test "fails when a question is still open", ctx do
    reviewed(ctx, open: "- Should a Candidate be able to withdraw?")

    assert_fails(ctx, "Open questions")
  end

  test "fails when two scenarios of one requirement share a name", ctx do
    reviewed(ctx, extra_scenario: "\nScenario: Apply\n  Given another listing")

    assert_fails(ctx, "REQ-007-1 has two scenarios named")
  end

  describe "--approved (the gate the test suite runs)" do
    defp gate(ctx, extra \\ []),
      do: SpecReview.run(["--specs-dir", ctx.specs, "--approved"] ++ extra)

    test "ignores a spec that is still a Draft, whatever state it is in", ctx do
      other_spec(ctx.specs)
      write(ctx.specs, "007-applications/spec.md", spec(open: "- Still open?"))
      commit(ctx.root, "draft")

      assert gate(ctx) == :ok
      assert_received {:mix_shell, :info, [msg]}
      assert msg =~ "0 approved"
    end

    test "passes a spec being approved now, when its review is current", ctx do
      sha = reviewed(ctx)
      commit(ctx.root, "review recorded")
      write(ctx.specs, "007-applications/spec.md", spec(review: review(sha), status: "Approved"))

      assert gate(ctx) == :ok
    end

    test "refuses a spec being approved now, when it changed after its review", ctx do
      sha = reviewed(ctx)
      commit(ctx.root, "review recorded")

      write(
        ctx.specs,
        "007-applications/spec.md",
        spec(review: review(sha), status: "Approved", narrative: "Changed (REQ-005-1).")
      )

      assert_raise Mix.Error, fn -> gate(ctx) end
      assert Enum.any?(problems(), &(&1 =~ "changed since"))
    end

    test "refuses a spec being approved now with no review", ctx do
      other_spec(ctx.specs)
      diagrams(ctx.specs)
      write(ctx.specs, "007-applications/spec.md", spec())
      commit(ctx.root, "draft")
      write(ctx.specs, "007-applications/spec.md", spec(status: "Approved"))

      assert_raise Mix.Error, fn -> gate(ctx) end
      assert Enum.any?(problems(), &(&1 =~ "Review before approval"))
    end

    test "lets a spec approved earlier be amended without a new review", ctx do
      sha = reviewed(ctx)
      write(ctx.specs, "007-applications/spec.md", spec(review: review(sha), status: "Approved"))
      commit(ctx.root, "approved")

      write(
        ctx.specs,
        "007-applications/spec.md",
        spec(review: review(sha), status: "In Progress", narrative: "Amended (REQ-005-1).")
      )

      assert gate(ctx) == :ok
    end

    test "still holds a spec approved earlier to the lasting checks", ctx do
      sha = reviewed(ctx)

      write(
        ctx.specs,
        "007-applications/spec.md",
        spec(review: review(sha), status: "Done (2026-12-01)")
      )

      commit(ctx.root, "done")

      write(
        ctx.specs,
        "007-applications/spec.md",
        spec(review: review(sha), status: "Done (2026-12-01)", covers: "REQ-007-1")
      )

      assert_raise Mix.Error, fn -> gate(ctx) end
      assert Enum.any?(problems(), &(&1 =~ "REQ-007-2 is in 0 rows"))
    end

    test "leaves out specs numbered below --from", ctx do
      other_spec(ctx.specs)
      write(ctx.specs, "007-applications/spec.md", spec(status: "Approved"))
      commit(ctx.root, "approved without review")

      assert gate(ctx, ["--from", "008"]) == :ok
    end
  end

  test "asks for a spec number", ctx do
    assert_raise Mix.Error, ~r/spec number/, fn ->
      SpecReview.run(["--specs-dir", ctx.specs])
    end
  end
end
