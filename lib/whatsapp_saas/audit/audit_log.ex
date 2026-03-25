defmodule WhatsappSaas.Audit.AuditLog do
  @moduledoc """
  Append-only audit event for important tenant actions.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Tenants.Tenant

  schema "audit_logs" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :binary_id
    field :payload, :map, default: %{}

    belongs_to :tenant, Tenant
    belongs_to :actor_user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:tenant_id, :actor_user_id, :action, :entity_type, :entity_id, :payload])
    |> validate_required([:tenant_id, :action, :entity_type, :entity_id])
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:actor_user_id)
  end
end
