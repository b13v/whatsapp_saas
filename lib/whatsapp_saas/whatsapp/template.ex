defmodule WhatsappSaas.WhatsApp.Template do
  @moduledoc """
  Normalized approved template available for outbound messaging.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Campaigns.Campaign
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.WhatsappAccount

  schema "templates" do
    field :provider_template_id, :string
    field :name, :string
    field :language, :string
    field :category, :string
    field :status, :string
    field :components, :map, default: %{}
    field :last_synced_at, :utc_datetime

    belongs_to :tenant, Tenant
    belongs_to :whatsapp_account, WhatsappAccount

    has_many :campaigns, Campaign

    timestamps(type: :utc_datetime)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :tenant_id,
      :whatsapp_account_id,
      :provider_template_id,
      :name,
      :language,
      :category,
      :status,
      :components,
      :last_synced_at
    ])
    |> validate_required([:tenant_id, :whatsapp_account_id, :name, :language])
    |> unique_constraint(:name, name: :templates_tenant_account_name_language_index)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:whatsapp_account_id)
  end
end
