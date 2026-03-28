defmodule WhatsappSaas.Repo.Migrations.AddConversationsCompositeIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(
                           :conversations,
                           [:tenant_id, :whatsapp_account_id, :contact_id, :status],
                           name: :conversations_tenant_account_contact_status_idx
                         )

    create_if_not_exists index(:audit_logs, [:action], name: :audit_logs_action_idx)
    create_if_not_exists index(:audit_logs, [:tenant_id, :action], name: :audit_logs_tenant_action_idx)
  end
end
