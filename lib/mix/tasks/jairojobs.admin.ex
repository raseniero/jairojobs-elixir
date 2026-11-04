defmodule Mix.Tasks.Jairojobs.Admin do
  @shortdoc "Promote or demote an admin by email (spec 001, REQ-001-10)"

  @moduledoc """
  Grants or removes the admin role outside the web UI.

      mix jairojobs.admin promote EMAIL
      mix jairojobs.admin demote  EMAIL

  Runs with the operator (`Scope.system/0`) scope and applies the rules in
  `Jairojobs.Accounts.promote_to_admin/2` and `demote_admin/2`: the target must
  exist and be confirmed, and the last admin cannot be demoted. Prints one line
  and exits non-zero on failure.
  """

  use Mix.Task

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope

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
  def execute(action, email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:error, "No account found for #{email}"}

      user ->
        case action do
          "promote" -> promote(user)
          "demote" -> demote(user)
        end
    end
  end

  defp promote(user) do
    case Accounts.promote_to_admin(Scope.system(), user) do
      {:ok, _admin} -> {:ok, "#{user.email} is now an admin"}
      {:error, :unconfirmed} -> {:error, "#{user.email} has not confirmed their email yet"}
      {:error, :unauthorized} -> {:error, "Not authorized to promote #{user.email}"}
    end
  end

  defp demote(user) do
    case Accounts.demote_admin(Scope.system(), user) do
      {:ok, demoted} ->
        {:ok, "#{user.email} is no longer an admin (now #{demoted.role})"}

      {:error, :not_admin} ->
        {:error, "#{user.email} is not an admin"}

      {:error, :last_admin} ->
        {:error, "#{user.email} is the only admin; promote someone else first"}

      {:error, :unauthorized} ->
        {:error, "Not authorized to demote #{user.email}"}

      {:error, %Ecto.Changeset{}} ->
        {:error, "Could not demote #{user.email}"}
    end
  end
end
