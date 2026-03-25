defmodule WhatsappSaas.Repo.Migrations.CreateContactConsents do
  use Ecto.Migration

  def change do
    create table(:contact_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      add :contact_id, references(:contacts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel, :string, null: false, default: "whatsapp"
      add :source, :string
      add :granted_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :proof, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:contact_consents, [:tenant_id])
    create index(:contact_consents, [:contact_id])
    create index(:contact_consents, [:channel])
  end
end
