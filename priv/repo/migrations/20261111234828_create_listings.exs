defmodule Jairojobs.Repo.Migrations.CreateListings do
  use Ecto.Migration

  # spec 003 — employer posting. Salary is stored in centavos (constitution §4.5).
  def change do
    create table(:listings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :region_id, references(:regions, type: :binary_id, on_delete: :restrict)
      add :status, :string, null: false, default: "draft"
      add :title, :string, null: false
      add :area, :string
      add :salary_min_centavos, :integer
      add :salary_max_centavos, :integer
      add :employment_type, :string
      add :schedule, :string
      add :description, :text
      add :requirements, :text
      add :benefits, :text
      add :business_name, :string
      add :business_about, :text
      add :rejection_reason, :text
      add :submitted_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:listings, [:user_id, :status])
    create index(:listings, [:region_id])

    create constraint(:listings, :listings_status_check,
             check:
               "status IN ('draft', 'pending', 'published', 'rejected', 'closed', 'taken_down')"
           )

    create constraint(:listings, :listings_employment_type_check,
             check:
               "employment_type IS NULL OR employment_type IN " <>
                 "('full_time', 'part_time', 'contract', 'temporary', 'internship')"
           )

    # Both empty, or a whole-peso monthly range of ₱1,000 to ₱1,000,000.
    create constraint(:listings, :listings_salary_check,
             check:
               "(salary_min_centavos IS NULL AND salary_max_centavos IS NULL) OR " <>
                 "(salary_min_centavos IS NOT NULL AND salary_max_centavos IS NOT NULL " <>
                 "AND salary_min_centavos >= 100000 AND salary_max_centavos >= salary_min_centavos " <>
                 "AND salary_max_centavos <= 100000000 " <>
                 "AND salary_min_centavos % 100 = 0 AND salary_max_centavos % 100 = 0)"
           )

    # Nothing leaves Draft / Rejected without a region, area, salary range, type,
    # description and a named business — whoever changes the status (specs 003, 004).
    create constraint(:listings, :listings_complete_unless_unsubmitted,
             check:
               "status IN ('draft', 'rejected') OR " <>
                 "(region_id IS NOT NULL AND area IS NOT NULL " <>
                 "AND salary_min_centavos IS NOT NULL AND salary_max_centavos IS NOT NULL " <>
                 "AND employment_type IS NOT NULL AND description IS NOT NULL " <>
                 "AND business_name IS NOT NULL)"
           )
  end
end
