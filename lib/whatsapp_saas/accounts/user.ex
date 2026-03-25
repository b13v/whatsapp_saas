defmodule WhatsappSaas.Accounts.User do
  @moduledoc """
  Tenant-scoped user record with role and status metadata.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Audit.AuditLog
  alias WhatsappSaas.Campaigns.Campaign
  alias WhatsappSaas.Inbox.Conversation
  alias WhatsappSaas.Tenants.Tenant

  @roles ~w(owner admin agent viewer)
  @statuses ~w(active invited disabled)

  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :confirmed_at, :utc_datetime
    field :role, :string, default: "owner"
    field :full_name, :string
    field :status, :string, default: "active"

    belongs_to :tenant, Tenant

    has_many :assigned_conversations, Conversation, foreign_key: :assigned_user_id
    has_many :created_campaigns, Campaign, foreign_key: :created_by_user_id
    has_many :audit_logs, AuditLog, foreign_key: :actor_user_id
    has_many :owned_tenants, Tenant, foreign_key: :owner_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :hashed_password,
      :confirmed_at,
      :tenant_id,
      :role,
      :full_name,
      :status
    ])
    |> validate_required([:email, :hashed_password, :role, :status])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:tenant_id)
  end
end
