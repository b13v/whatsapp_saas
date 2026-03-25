defmodule WhatsappSaas.Contacts.Contact do
  @moduledoc """
  Customer contact stored within a tenant workspace.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Campaigns.CampaignDelivery
  alias WhatsappSaas.Contacts.ContactConsent
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Tenants.Tenant

  @opt_in_statuses ~w(unknown subscribed unsubscribed)

  schema "contacts" do
    field :external_wa_id, :string
    field :phone_e164, :string
    field :name, :string
    field :first_name, :string
    field :last_name, :string
    field :locale, :string
    field :tags, :map, default: %{}
    field :notes, :string
    field :opt_in_status, :string, default: "unknown"
    field :opted_in_at, :utc_datetime
    field :unsubscribed_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :tenant, Tenant

    has_many :conversations, Conversation
    has_many :messages, Message
    has_many :campaign_deliveries, CampaignDelivery
    has_many :contact_consents, ContactConsent

    timestamps(type: :utc_datetime)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :tenant_id,
      :external_wa_id,
      :phone_e164,
      :name,
      :first_name,
      :last_name,
      :locale,
      :tags,
      :notes,
      :opt_in_status,
      :opted_in_at,
      :unsubscribed_at,
      :last_seen_at,
      :metadata
    ])
    |> validate_required([:tenant_id, :phone_e164, :opt_in_status])
    |> validate_length(:phone_e164, min: 5)
    |> validate_inclusion(:opt_in_status, @opt_in_statuses)
    |> unique_constraint(:phone_e164, name: :contacts_tenant_id_phone_e164_index)
    |> foreign_key_constraint(:tenant_id)
  end
end
