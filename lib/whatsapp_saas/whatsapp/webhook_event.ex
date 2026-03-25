defmodule WhatsappSaas.WhatsApp.WebhookEvent do
  @moduledoc """
  Raw provider webhook payload persisted before async processing.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Tenants.Tenant

  @processing_statuses ~w(pending processed failed)

  schema "webhook_events" do
    field :provider, :string
    field :provider_event_id, :string
    field :topic, :string
    field :payload, :map, default: %{}
    field :processing_status, :string, default: "pending"
    field :processed_at, :utc_datetime
    field :error_message, :string

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :tenant_id,
      :provider,
      :provider_event_id,
      :topic,
      :payload,
      :processing_status,
      :processed_at,
      :error_message
    ])
    |> validate_required([:provider, :payload, :processing_status])
    |> validate_inclusion(:processing_status, @processing_statuses)
    |> unique_constraint(:provider_event_id,
      name: :webhook_events_provider_provider_event_id_index
    )
    |> foreign_key_constraint(:tenant_id)
  end
end
