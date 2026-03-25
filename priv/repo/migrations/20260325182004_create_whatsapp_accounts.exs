defmodule WhatsappSaas.Repo.Migrations.CreateWhatsappAccounts do
  use Ecto.Migration

  def change do
    create table(:whatsapp_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :external_account_id, :string
      add :external_waba_id, :string
      add :external_phone_number_id, :string
      add :display_name, :string
      add :phone_number, :string
      add :quality_rating, :string
      add :status, :string, null: false, default: "pending"
      add :onboarding_mode, :string
      add :connected_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:whatsapp_accounts, [:tenant_id])

    create unique_index(:whatsapp_accounts, [:external_account_id],
             where: "external_account_id IS NOT NULL"
           )

    create index(:whatsapp_accounts, [:external_waba_id])
    create index(:whatsapp_accounts, [:external_phone_number_id])
  end
end
