defmodule Jairojobs.Repo.Migrations.AddBusinessDetailsToUsers do
  use Ecto.Migration

  # spec 003 — REQ-003-2: the business an Employer (or Admin) posts listings for.
  def change do
    alter table(:users) do
      add :business_name, :string
      add :business_about, :string, size: 500
    end

    create constraint(:users, :users_business_name_length,
             check: "business_name IS NULL OR char_length(business_name) BETWEEN 2 AND 80"
           )
  end
end
