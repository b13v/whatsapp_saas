defmodule WhatsappSaas.Campaigns.CampaignDelivery do
  @moduledoc """
  Delivery status of a campaign for a specific contact.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Campaigns.Campaign
  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Inbox.Message
  alias WhatsappSaas.Tenants.Tenant

  @statuses ~w(queued sent delivered read failed skipped)

  schema "campaign_deliveries" do
    field :status, :string, default: "queued"
    field :error_code, :string
    field :error_message, :string

    belongs_to :tenant, Tenant
    belongs_to :campaign, Campaign
    belongs_to :contact, Contact
    belongs_to :message, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :tenant_id,
      :campaign_id,
      :contact_id,
      :message_id,
      :status,
      :error_code,
      :error_message
    ])
    |> validate_required([:tenant_id, :campaign_id, :contact_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:contact_id, name: :campaign_deliveries_campaign_id_contact_id_index)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:campaign_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:message_id)
  end
end
