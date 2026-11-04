defmodule Jairojobs.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Jairojobs.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Jairojobs.Accounts.User

  defstruct user: nil, system: false

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  # spec 001 — REQ-001-9: the role travels with the scope.

  @doc """
  The role of the scoped user, or `nil` for a visitor.
  """
  def role(%__MODULE__{user: %User{role: role}}), do: role
  def role(_scope), do: nil

  @doc """
  `true` when the scoped user is an admin.

  The system scope is **not** an admin here: it is only honoured by the
  promote/demote functions in `Jairojobs.Accounts`.
  """
  def admin?(scope), do: role(scope) == :admin

  @doc """
  The operator scope used by privileged commands (REQ-001-10). It carries no
  user and must never be mounted from a web request.
  """
  def system, do: %__MODULE__{user: nil, system: true}

  @doc """
  `true` for the scope returned by `system/0`.
  """
  def system?(%__MODULE__{system: true}), do: true
  def system?(_scope), do: false
end
