defmodule WhatsappSaas.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:tenant_id])
    create index(:audit_logs, [:actor_user_id])
    create index(:audit_logs, [:entity_type])
    create index(:audit_logs, [:entity_id])
    create index(:audit_logs, [:inserted_at])
  end
end
