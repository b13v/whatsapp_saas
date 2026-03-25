defmodule WhatsappSaas.Repo.Migrations.CreateUsageCounters do
  use Ecto.Migration

  def change do
    create table(:usage_counters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :metric_date, :date, null: false
      add :messages_sent, :integer, null: false, default: 0
      add :messages_received, :integer, null: false, default: 0
      add :templates_sent, :integer, null: false, default: 0
      add :active_contacts, :integer, null: false, default: 0
      add :provider_cost_cents, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:usage_counters, [:tenant_id, :metric_date])
  end
end
