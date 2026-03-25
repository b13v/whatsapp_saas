defmodule WhatsappSaas.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :external_wa_id, :string
      add :phone_e164, :string, null: false
      add :name, :string
      add :first_name, :string
      add :last_name, :string
      add :locale, :string
      add :tags, :map, null: false, default: %{}
      add :notes, :text
      add :opt_in_status, :string, null: false, default: "unknown"
      add :opted_in_at, :utc_datetime
      add :unsubscribed_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:tenant_id])
    create index(:contacts, [:phone_e164])
    create unique_index(:contacts, [:tenant_id, :phone_e164])
    create index(:contacts, [:external_wa_id])
  end
end
