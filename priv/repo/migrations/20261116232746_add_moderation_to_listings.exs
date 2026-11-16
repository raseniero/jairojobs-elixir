defmodule Jairojobs.Repo.Migrations.AddModerationToListings do
  use Ecto.Migration

  # spec 004 — admin moderation. The latest decision on a listing: when it was
  # made and by which Admin. What the decision was follows from the status.
  # `published_at` is set once, on approval, and survives a take-down: it is the
  # "posted" date for spec 005.
  def change do
    alter table(:listings) do
      add :takedown_reason, :text
      add :published_at, :utc_datetime_usec
      add :decided_at, :utc_datetime_usec
      # Deleting an Admin's account keeps their decisions, without a name (plan decision 3).
      add :decided_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    # The approval queue (Pending, longest-waiting first), its count, and the status lists.
    create index(:listings, [:status, :submitted_at])
  end
end
