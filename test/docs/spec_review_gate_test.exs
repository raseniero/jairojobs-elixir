defmodule Jairojobs.Docs.SpecReviewGateTest do
  # The gate before a spec is approved (constitution §6; docs/README.md, Feature
  # lifecycle, step 1). Runs in `mix precommit`, so a spec cannot be committed as
  # Approved without a current "Review before approval" section.
  #
  # Not async: swaps the global Mix shell to capture the task's output.
  use ExUnit.Case, async: false

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "every approved spec from 005 onwards passes mix jairojobs.spec_review" do
    assert Mix.Tasks.Jairojobs.SpecReview.run(["--approved"]) == :ok
  rescue
    error in Mix.Error ->
      flunk(error.message <> "\n" <> Enum.join(problems(), "\n"))
  end

  defp problems do
    receive do
      {:mix_shell, :error, [line]} -> [line | problems()]
    after
      0 -> []
    end
  end
end
