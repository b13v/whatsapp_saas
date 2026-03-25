defmodule WhatsappSaas.Repo.Migrations.CreateCampaigns do
  use Ecto.Migration

  def change do
    create table(:campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :whatsapp_account_id,
          references(:whatsapp_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :template_id, references(:templates, type: :binary_id, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :audience_filter, :map, null: false, default: %{}
      add :status, :string, null: false, default: "draft"
      add :scheduled_at, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:campaigns, [:tenant_id])
    create index(:campaigns, [:whatsapp_account_id])
    create index(:campaigns, [:template_id])
    create index(:campaigns, [:status])
    create index(:campaigns, [:scheduled_at])
  end
end
