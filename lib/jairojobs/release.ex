defmodule Jairojobs.Release do
  @moduledoc """
  Tasks the operator runs in production, where Mix is not installed.

      bin/jairojobs eval 'Jairojobs.Release.migrate()'
      bin/jairojobs eval 'Jairojobs.Release.seed_regions()'
      bin/jairojobs eval 'Jairojobs.Release.promote_admin("someone@example.com")'
      bin/jairojobs eval 'Jairojobs.Release.demote_admin("someone@example.com")'

  On Fly.io, prefix with `fly ssh console -C "/app/bin/jairojobs eval '...'"`.

  `promote_admin/1` and `demote_admin/1` are the production form of
  `mix jairojobs.admin` (spec 001, REQ-001-10); both go through `admin/2`.
  `seed_regions/0` inserts the launch regions (spec 002, REQ-002-5), which
  `mix setup` does in development; it only inserts what is missing.
  """
  @app :jairojobs

  alias Jairojobs.Accounts
  alias Jairojobs.Accounts.Scope

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Inserts the launch regions that are missing (REQ-002-5)."
  def seed_regions do
    with_repo(fn -> Jairojobs.Regions.seed_launch_regions() end)
  end

  @doc "Makes the account with this email an admin (REQ-001-10). Halts non-zero on failure."
  def promote_admin(email), do: with_repo(fn -> admin("promote", email) end) |> report()

  @doc "Removes the admin role from the account with this email (REQ-001-10). Halts non-zero on failure."
  def demote_admin(email), do: with_repo(fn -> admin("demote", email) end) |> report()

  @doc """
  Promotes or demotes by email with the operator scope. Returns `{:ok, message}`
  or `{:error, message}`, one line either way. Shared with `mix jairojobs.admin`.
  """
  def admin(action, email) when action in ["promote", "demote"] do
    case Accounts.get_user_by_email(email) do
      nil -> {:error, "No account found for #{email}"}
      user when action == "promote" -> promote(user)
      user -> demote(user)
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

  defp report({:ok, message}), do: IO.puts(message)

  defp report({:error, message}) do
    IO.puts(:stderr, message)
    System.halt(1)
  end

  defp with_repo(fun) do
    load_app()
    [repo] = repos()
    {:ok, result, _apps} = Ecto.Migrator.with_repo(repo, fn _repo -> fun.() end)
    result
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
