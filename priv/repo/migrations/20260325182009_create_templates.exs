defmodule WhatsappSaas.Repo.Migrations.CreateTemplates do
  use Ecto.Migration

  def change do
    create table(:templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :whatsapp_account_id,
          references(:whatsapp_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      add :provider_template_id, :string
      add :name, :string, null: false
      add :language, :string, null: false
      add :category, :string
      add :status, :string
      add :components, :map, null: false, default: %{}
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:templates, [:tenant_id])
    create index(:templates, [:whatsapp_account_id])
    create index(:templates, [:status])

    create unique_index(
             :templates,
             [:tenant_id, :whatsapp_account_id, :name, :language],
             name: :templates_tenant_account_name_language_index
           )
  end
end
