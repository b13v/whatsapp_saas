defmodule WhatsappSaas.Billing.UsageCounter do
  @moduledoc """
  Daily usage aggregate for plan gating and billing placeholders.
  """

  use WhatsappSaas.Schema

  alias WhatsappSaas.Tenants.Tenant

  schema "usage_counters" do
    field :metric_date, :date
    field :messages_sent, :integer, default: 0
    field :messages_received, :integer, default: 0
    field :templates_sent, :integer, default: 0
    field :active_contacts, :integer, default: 0
    field :provider_cost_cents, :integer, default: 0

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime)
  end

  def changeset(counter, attrs) do
    counter
    |> cast(attrs, [
      :tenant_id,
      :metric_date,
      :messages_sent,
      :messages_received,
      :templates_sent,
      :active_contacts,
      :provider_cost_cents
    ])
    |> validate_required([:tenant_id, :metric_date])
    |> validate_number(:messages_sent, greater_than_or_equal_to: 0)
    |> validate_number(:messages_received, greater_than_or_equal_to: 0)
    |> validate_number(:templates_sent, greater_than_or_equal_to: 0)
    |> validate_number(:active_contacts, greater_than_or_equal_to: 0)
    |> validate_number(:provider_cost_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:metric_date, name: :usage_counters_tenant_id_metric_date_index)
    |> foreign_key_constraint(:tenant_id)
  end
end
