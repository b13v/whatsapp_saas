defmodule WhatsappSaas.Inbox.Message do
  @moduledoc """
  Inbound, outbound, or system message inside a conversation.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Campaigns.CampaignDelivery
  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Inbox.Conversation
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.WhatsappAccount

  @directions ~w(inbound outbound system)
  @kinds ~w(text template image document status)
  @statuses ~w(queued sent delivered read failed)

  schema "messages" do
    field :direction, :string
    field :kind, :string
    field :provider_message_id, :string
    field :status, :string, default: "queued"
    field :body, :string
    field :payload, :map, default: %{}
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :read_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :error_code, :string
    field :error_message, :string

    belongs_to :tenant, Tenant
    belongs_to :conversation, Conversation
    belongs_to :whatsapp_account, WhatsappAccount
    belongs_to :contact, Contact

    has_many :campaign_deliveries, CampaignDelivery

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :tenant_id,
      :conversation_id,
      :whatsapp_account_id,
      :contact_id,
      :direction,
      :kind,
      :provider_message_id,
      :status,
      :body,
      :payload,
      :sent_at,
      :delivered_at,
      :read_at,
      :failed_at,
      :error_code,
      :error_message
    ])
    |> validate_required([
      :tenant_id,
      :conversation_id,
      :whatsapp_account_id,
      :contact_id,
      :direction,
      :kind,
      :status
    ])
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:provider_message_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:conversation_id)
    |> foreign_key_constraint(:whatsapp_account_id)
    |> foreign_key_constraint(:contact_id)
  end
end
