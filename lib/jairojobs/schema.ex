defmodule Jairojobs.Schema do
  @moduledoc """
  Shared schema defaults (ADR-0004).

  `use Jairojobs.Schema` instead of `use Ecto.Schema` in every schema so that:

    * primary keys are app-generated, time-ordered **UUID v7** (`Ecto.UUID`, `version: 7`)
    * foreign keys are `Ecto.UUID`
    * timestamps are `:utc_datetime_usec`

  Migrations get the matching defaults from `config :jairojobs, Jairojobs.Repo,
  migration_primary_key: ..., migration_foreign_key: ..., migration_timestamps: ...`.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Ecto.UUID, autogenerate: [version: 7]}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
