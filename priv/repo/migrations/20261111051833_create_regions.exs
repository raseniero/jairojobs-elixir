defmodule Jairojobs.Repo.Migrations.CreateRegions do
  use Ecto.Migration

  # spec 002 — REQ-002-2 (name + slug rules), REQ-002-4 (active flag)
  def change do
    create table(:regions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :citext, null: false
      add :slug, :string, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:regions, [:name])
    create unique_index(:regions, [:slug])

    create constraint(:regions, :regions_slug_format, check: "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'")

    create constraint(:regions, :regions_name_length,
             check: "char_length(name::text) BETWEEN 1 AND 80"
           )
  end
end
