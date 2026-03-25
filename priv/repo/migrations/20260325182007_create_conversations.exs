defmodule WhatsappSaas.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :whatsapp_account_id,
          references(:whatsapp_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :contact_id, references(:contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :assigned_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "open"
      add :category, :string
      add :source, :string
      add :unread_count, :integer, null: false, default: 0
      add :last_message_at, :utc_datetime
      add :closed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:tenant_id])
    create index(:conversations, [:whatsapp_account_id])
    create index(:conversations, [:contact_id])
    create index(:conversations, [:assigned_user_id])
    create index(:conversations, [:status])
    create index(:conversations, [:last_message_at])
  end
end
