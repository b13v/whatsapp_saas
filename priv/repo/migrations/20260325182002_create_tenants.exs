defmodule WhatsappSaas.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :status, :string, null: false, default: "active"
      add :plan, :string, null: false, default: "starter"
      add :vertical, :string, null: false, default: "clinic"
      add :country, :string
      add :timezone, :string
      add :billing_email, :string
      add :onboarding_status, :string, null: false, default: "not_started"
      add :owner_user_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tenants, [:slug])
    create index(:tenants, [:owner_user_id])
  end
end
