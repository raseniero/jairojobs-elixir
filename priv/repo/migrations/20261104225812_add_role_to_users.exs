defmodule Jairojobs.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  # spec 001 — REQ-001-2 / REQ-001-9 / REQ-001-11 (plan decisions 2, 3)
  def change do
    alter table(:users) do
      add :role, :string, null: false
      add :previous_role, :string
    end

    create constraint(:users, :users_role_check,
             check: "role IN ('candidate', 'employer', 'admin')"
           )

    create constraint(:users, :users_previous_role_check,
             check: "previous_role IS NULL OR previous_role IN ('candidate', 'employer')"
           )

    create index(:users, [:role])
  end
end
