defmodule WhatsappSaas.Campaigns.Campaign do
  @moduledoc """
  Scheduled or running outbound campaign scoped to a tenant.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Campaigns.CampaignDelivery
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.{Template, WhatsappAccount}

  @statuses ~w(draft scheduled running completed failed cancelled)

  schema "campaigns" do
    field :name, :string
    field :audience_filter, :map, default: %{}
    field :status, :string, default: "draft"
    field :scheduled_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :tenant, Tenant
    belongs_to :whatsapp_account, WhatsappAccount
    belongs_to :template, Template
    belongs_to :created_by_user, User

    has_many :campaign_deliveries, CampaignDelivery

    timestamps(type: :utc_datetime)
  end

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :tenant_id,
      :whatsapp_account_id,
      :template_id,
      :created_by_user_id,
      :name,
      :audience_filter,
      :status,
      :scheduled_at,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :tenant_id,
      :whatsapp_account_id,
      :template_id,
      :created_by_user_id,
      :name,
      :status
    ])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:whatsapp_account_id)
    |> foreign_key_constraint(:template_id)
    |> foreign_key_constraint(:created_by_user_id)
  end
end
