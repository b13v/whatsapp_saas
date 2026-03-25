defmodule WhatsappSaas.Repo.Migrations.CreateOnboardingSessions do
  use Ecto.Migration

  def change do
    create table(:onboarding_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :whatsapp_account_id,
          references(:whatsapp_accounts, type: :binary_id, on_delete: :nilify_all)

      add :provider, :string, null: false
      add :external_setup_id, :string
      add :setup_link, :text
      add :state, :string, null: false, default: "created"
      add :redirect_url, :text
      add :error_code, :string
      add :error_message, :text
      add :expires_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:onboarding_sessions, [:tenant_id])
    create index(:onboarding_sessions, [:whatsapp_account_id])

    create unique_index(:onboarding_sessions, [:external_setup_id],
             where: "external_setup_id IS NOT NULL"
           )

    create index(:onboarding_sessions, [:state])
  end
end
