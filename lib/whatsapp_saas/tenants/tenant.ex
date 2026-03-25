defmodule WhatsappSaas.Tenants.Tenant do
  @moduledoc """
  Workspace record for a clinic or salon tenant.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Audit.AuditLog
  alias WhatsappSaas.Billing.UsageCounter
  alias WhatsappSaas.Campaigns.{Campaign, CampaignDelivery}
  alias WhatsappSaas.Contacts.{Contact, ContactConsent}
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Onboarding.OnboardingSession
  alias WhatsappSaas.WhatsApp.{Template, WebhookEvent, WhatsappAccount}

  @statuses ~w(active suspended archived)
  @plans ~w(starter growth agency)
  @verticals ~w(clinic dental beauty)
  @onboarding_statuses ~w(not_started in_progress connected failed)

  schema "tenants" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :plan, :string, default: "starter"
    field :vertical, :string, default: "clinic"
    field :country, :string
    field :timezone, :string
    field :billing_email, :string
    field :onboarding_status, :string, default: "not_started"

    belongs_to :owner_user, User

    has_many :users, User
    has_many :whatsapp_accounts, WhatsappAccount
    has_many :onboarding_sessions, OnboardingSession
    has_many :contacts, Contact
    has_many :conversations, Conversation
    has_many :messages, Message
    has_many :templates, Template
    has_many :campaigns, Campaign
    has_many :campaign_deliveries, CampaignDelivery
    has_many :webhook_events, WebhookEvent
    has_many :audit_logs, AuditLog
    has_many :usage_counters, UsageCounter
    has_many :contact_consents, ContactConsent

    timestamps(type: :utc_datetime)
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [
      :name,
      :slug,
      :status,
      :plan,
      :vertical,
      :country,
      :timezone,
      :billing_email,
      :onboarding_status,
      :owner_user_id
    ])
    |> validate_required([:name, :slug, :status, :plan, :vertical, :onboarding_status])
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_format(:billing_email, ~r/^[^\s]+@[^\s]+$/, allow_blank: true)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:plan, @plans)
    |> validate_inclusion(:vertical, @verticals)
    |> validate_inclusion(:onboarding_status, @onboarding_statuses)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:owner_user_id)
  end
end
