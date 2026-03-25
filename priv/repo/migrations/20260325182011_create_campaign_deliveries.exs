defmodule WhatsappSaas.Repo.Migrations.CreateCampaignDeliveries do
  use Ecto.Migration

  def change do
    create table(:campaign_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :contact_id, references(:contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, null: false, default: "queued"
      add :error_code, :string
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:campaign_deliveries, [:tenant_id])
    create index(:campaign_deliveries, [:campaign_id])
    create index(:campaign_deliveries, [:contact_id])
    create index(:campaign_deliveries, [:message_id])
    create unique_index(:campaign_deliveries, [:campaign_id, :contact_id])
  end
end
