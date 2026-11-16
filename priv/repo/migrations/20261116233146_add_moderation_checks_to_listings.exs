defmodule Jairojobs.Repo.Migrations.AddModerationChecksToListings do
  use Ecto.Migration

  # spec 004 — what an Admin decision must leave behind, whoever writes the row
  # (plan decision 12).
  #
  # These would fail on a table that already holds Published, Closed, Rejected or
  # Taken down rows without the columns below. None can exist: before spec 004
  # nothing could put a listing into those statuses (only a test-only helper,
  # removed before this migration), and there is no production database yet.
  def change do
    # Approval is the only way to Published, and it stamps the time. Closed and
    # Taken down are only reached from Published, so they carry it too.
    create constraint(:listings, :listings_published_has_time,
             check:
               "status NOT IN ('published', 'closed', 'taken_down') OR published_at IS NOT NULL"
           )

    create constraint(:listings, :listings_rejected_has_reason,
             check: "status <> 'rejected' OR rejection_reason IS NOT NULL"
           )

    create constraint(:listings, :listings_taken_down_has_reason,
             check: "status <> 'taken_down' OR takedown_reason IS NOT NULL"
           )
  end
end
