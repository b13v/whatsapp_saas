defmodule WhatsappSaas.Repo.Migrations.AddTenantsOwnerUserForeignKey do
  use Ecto.Migration

  def up do
    execute """
            ALTER TABLE tenants
            ADD CONSTRAINT tenants_owner_user_id_fkey
            FOREIGN KEY (owner_user_id)
            REFERENCES users(id)
            ON DELETE SET NULL
            """,
            """
            ALTER TABLE tenants
            DROP CONSTRAINT tenants_owner_user_id_fkey
            """
  end

  def down do
    execute """
            ALTER TABLE tenants
            DROP CONSTRAINT tenants_owner_user_id_fkey
            """,
            """
            ALTER TABLE tenants
            ADD CONSTRAINT tenants_owner_user_id_fkey
            FOREIGN KEY (owner_user_id)
            REFERENCES users(id)
            ON DELETE SET NULL
            """
  end
end
