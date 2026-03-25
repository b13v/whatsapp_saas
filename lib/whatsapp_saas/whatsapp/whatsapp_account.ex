defmodule WhatsappSaas.WhatsApp.WhatsappAccount do
  @moduledoc """
  Provider-backed WhatsApp account connected to a tenant.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Campaigns.Campaign
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Onboarding.OnboardingSession
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.Template

  @providers ~w(kapso)
  @statuses ~w(pending connected disconnected failed)

  schema "whatsapp_accounts" do
    field :provider, :string
    field :external_account_id, :string
    field :external_waba_id, :string
    field :external_phone_number_id, :string
    field :display_name, :string
    field :phone_number, :string
    field :quality_rating, :string
    field :status, :string, default: "pending"
    field :onboarding_mode, :string
    field :connected_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :tenant, Tenant

    has_many :onboarding_sessions, OnboardingSession
    has_many :conversations, Conversation
    has_many :messages, Message
    has_many :templates, Template
    has_many :campaigns, Campaign

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :tenant_id,
      :provider,
      :external_account_id,
      :external_waba_id,
      :external_phone_number_id,
      :display_name,
      :phone_number,
      :quality_rating,
      :status,
      :onboarding_mode,
      :connected_at,
      :metadata
    ])
    |> validate_required([:tenant_id, :provider, :status])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:external_account_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
