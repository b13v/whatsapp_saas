defmodule WhatsappSaas.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :whatsapp_account_id,
          references(:whatsapp_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :contact_id, references(:contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :direction, :string, null: false
      add :kind, :string, null: false
      add :provider_message_id, :string
      add :status, :string, null: false, default: "queued"
      add :body, :text
      add :payload, :map, null: false, default: %{}
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :read_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :error_code, :string
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:tenant_id])
    create index(:messages, [:conversation_id])
    create index(:messages, [:whatsapp_account_id])
    create index(:messages, [:contact_id])
    create index(:messages, [:status])

    create unique_index(:messages, [:provider_message_id],
             where: "provider_message_id IS NOT NULL"
           )
  end
end
