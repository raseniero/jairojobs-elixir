defmodule Jairojobs.Repo.Migrations.AddPublicAddressChecks do
  use Ecto.Migration

  # spec 005 — REQ-005-6, plan decision 3. What a public address must be, whoever
  # writes the row.
  #
  # These come after the migration that gives addresses to listings approved
  # before spec 005: until that has run, such a listing has a published time and
  # no slug, and the first check would refuse the table as it is.
  def change do
    # Approved once means it has an address, for good: a Published, Closed or
    # Taken down listing has a slug, and a listing that was never approved has none.
    create constraint(:listings, :listings_slug_iff_approved,
             check: "(slug IS NULL) = (published_at IS NULL)"
           )

    # Needed by the foreign key below; it adds nothing the two existing unique
    # indexes do not already guarantee.
    create unique_index(:listing_addresses, [:listing_id, :region_id, :slug])

    # A listing's current address (its region and slug) is one of its own recorded
    # addresses. `:nothing` refuses at the end of the statement, so a clean-up can
    # remove a listing and its addresses in one statement; nothing else can.
    alter table(:listings) do
      modify :slug,
             references(:listing_addresses,
               column: :slug,
               type: :string,
               with: [id: :listing_id, region_id: :region_id],
               name: :listings_current_address_fkey,
               on_delete: :nothing
             ),
             from: :string
    end
  end
end
