defmodule Jairojobs.FailingMailAdapter do
  @moduledoc """
  A mail adapter that never delivers, for the tests of what happens when an
  email cannot be sent (spec 004 — REQ-004-9, REQ-004-10).

  By default it answers the way a mail service that refuses the message does,
  `{:error, :unavailable}`. Configured with `raise: true` it raises instead,
  the way a broken connection inside an adapter can.
  """
  use Swoosh.Adapter

  @impl true
  def deliver(_email, config) do
    if config[:raise] do
      raise "mail service unreachable"
    else
      {:error, :unavailable}
    end
  end
end
