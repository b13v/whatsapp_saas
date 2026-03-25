defmodule WhatsappSaas.Repo.Migrations.AddTenantFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :nilify_all)
      add :role, :string, null: false, default: "owner"
      add :full_name, :string
      add :status, :string, null: false, default: "active"
    end

    create index(:users, [:tenant_id])
  end
end
