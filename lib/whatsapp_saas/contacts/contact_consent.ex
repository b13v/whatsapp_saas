defmodule WhatsappSaas.Contacts.ContactConsent do
  @moduledoc """
  Audit-friendly consent record for a contact and channel.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Tenants.Tenant

  @channels ~w(whatsapp)

  schema "contact_consents" do
    field :channel, :string, default: "whatsapp"
    field :source, :string
    field :granted_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :proof, :map, default: %{}

    belongs_to :tenant, Tenant
    belongs_to :contact, Contact

    timestamps(type: :utc_datetime)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:tenant_id, :contact_id, :channel, :source, :granted_at, :revoked_at, :proof])
    |> validate_required([:tenant_id, :contact_id, :channel])
    |> validate_inclusion(:channel, @channels)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:contact_id)
  end
end
