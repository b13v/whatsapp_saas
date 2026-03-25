defmodule WhatsappSaas.Inbox.Conversation do
  @moduledoc """
  Inbox thread between a tenant account and a contact.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Inbox.Message
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.WhatsappAccount

  @statuses ~w(open waiting closed)

  schema "conversations" do
    field :status, :string, default: "open"
    field :category, :string
    field :source, :string
    field :unread_count, :integer, default: 0
    field :last_message_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :tenant, Tenant
    belongs_to :whatsapp_account, WhatsappAccount
    belongs_to :contact, Contact
    belongs_to :assigned_user, User

    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [
      :tenant_id,
      :whatsapp_account_id,
      :contact_id,
      :assigned_user_id,
      :status,
      :category,
      :source,
      :unread_count,
      :last_message_at,
      :closed_at,
      :metadata
    ])
    |> validate_required([:tenant_id, :whatsapp_account_id, :contact_id, :status, :unread_count])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:unread_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:whatsapp_account_id)
    |> foreign_key_constraint(:contact_id)
    |> foreign_key_constraint(:assigned_user_id)
  end
end
