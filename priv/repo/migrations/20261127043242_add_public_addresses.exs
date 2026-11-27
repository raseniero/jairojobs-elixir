defmodule Jairojobs.Repo.Migrations.AddPublicAddresses do
  use Ecto.Migration

  # spec 005 — REQ-005-6. A listing's public address is /jobs/<region slug>/<slug>.
  #
  # `listings.slug` is the current one, set on approval. `listing_addresses` holds
  # every address a listing has or ever had, the current one included: one row
  # each, only ever inserted. A listing moved to another region gains a row and
  # keeps the old one, which is how the old address forwards.
  def change do
    alter table(:listings) do
      add :slug, :string
    end

    create table(:listing_addresses, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # A listing that has an address is never deleted, and neither is its region.
      # `:nothing` refuses the delete like `:restrict`, but at the end of the
      # statement, so a clean-up can remove a listing and its addresses together.
      add :listing_id, references(:listings, type: :binary_id, on_delete: :nothing), null: false
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict), null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # An address belongs to one listing for good: it is never given to another.
    create unique_index(:listing_addresses, [:region_id, :slug])

    # A listing has one address per region, so one moved back finds the one it had.
    create unique_index(:listing_addresses, [:listing_id, :region_id])

    # The same shape as a region's slug, and at most 60 characters.
    create constraint(:listing_addresses, :listing_addresses_slug_format,
             check: "slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) <= 60"
           )
  end
end
