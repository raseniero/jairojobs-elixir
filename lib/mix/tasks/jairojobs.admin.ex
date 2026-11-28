defmodule Mix.Tasks.Jairojobs.Admin do
  @shortdoc "Promote or demote an admin by email (spec 001, REQ-001-10)"

  @moduledoc """
  Grants or removes the admin role outside the web UI.

      mix jairojobs.admin promote EMAIL
      mix jairojobs.admin demote  EMAIL

  Runs with the operator (`Scope.system/0`) scope through `Jairojobs.Release.admin/2`
  (which production calls via `bin/jairojobs eval`) and applies the rules in
  `Jairojobs.Accounts.promote_to_admin/2` and `demote_admin/2`: the target must
  exist and be confirmed, and the last admin cannot be demoted. Prints one line
  and exits non-zero on failure.
  """

  use Mix.Task

  @usage "Usage: mix jairojobs.admin promote|demote EMAIL"

  @impl Mix.Task
  def run([action, email]) when action in ["promote", "demote"] do
    Mix.Task.run("app.start")

    case execute(action, email) do
      {:ok, message} -> Mix.shell().info(message)
      {:error, message} -> Mix.raise(message)
    end
  end

  def run(_args), do: Mix.raise(@usage)

  @doc false
  defdelegate execute(action, email), to: Jairojobs.Release, as: :admin
end
