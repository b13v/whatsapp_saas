defmodule WhatsappSaas.Repo.Migrations.CreateWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :nilify_all)
      add :provider, :string, null: false
      add :provider_event_id, :string
      add :topic, :string
      add :payload, :map, null: false, default: %{}
      add :processing_status, :string, null: false, default: "pending"
      add :processed_at, :utc_datetime
      add :error_message, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:webhook_events, [:tenant_id])
    create index(:webhook_events, [:provider])
    create index(:webhook_events, [:topic])
    create index(:webhook_events, [:processing_status])
    create index(:webhook_events, [:inserted_at])

    create unique_index(:webhook_events, [:provider, :provider_event_id],
             where: "provider_event_id IS NOT NULL"
           )
  end
end
