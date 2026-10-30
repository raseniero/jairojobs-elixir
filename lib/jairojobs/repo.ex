defmodule Jairojobs.Repo do
  use Ecto.Repo,
    otp_app: :jairojobs,
    adapter: Ecto.Adapters.Postgres
end
