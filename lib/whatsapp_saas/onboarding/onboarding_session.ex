defmodule WhatsappSaas.Onboarding.OnboardingSession do
  @moduledoc """
  Tracks tenant onboarding progress with the WhatsApp provider.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.WhatsappAccount

  @providers ~w(kapso)
  @states ~w(created link_generated callback_received connected failed)

  schema "onboarding_sessions" do
    field :provider, :string
    field :external_setup_id, :string
    field :setup_link, :string
    field :state, :string, default: "created"
    field :redirect_url, :string
    field :error_code, :string
    field :error_message, :string
    field :expires_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :tenant, Tenant
    belongs_to :whatsapp_account, WhatsappAccount

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :tenant_id,
      :whatsapp_account_id,
      :provider,
      :external_setup_id,
      :setup_link,
      :state,
      :redirect_url,
      :error_code,
      :error_message,
      :expires_at,
      :completed_at,
      :metadata
    ])
    |> validate_required([:tenant_id, :provider, :state])
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:state, @states)
    |> unique_constraint(:external_setup_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:whatsapp_account_id)
  end
end
