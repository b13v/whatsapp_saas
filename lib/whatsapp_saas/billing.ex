defmodule WhatsappSaas.Billing do
  @moduledoc """
  Minimal usage and plan gating helpers.
  """

  import Ecto.Query, warn: false

  alias WhatsappSaas.Billing.UsageCounter
  alias WhatsappSaas.Repo

  @plan_limits %{
    "starter" => %{whatsapp_accounts: 1, users: 5, campaigns: true},
    "growth" => %{whatsapp_accounts: 3, users: 20, campaigns: true},
    "agency" => %{whatsapp_accounts: 10, users: 100, campaigns: true}
  }

  def get_usage_for_date(tenant_id, metric_date) do
    UsageCounter
    |> where([counter], counter.tenant_id == ^tenant_id and counter.metric_date == ^metric_date)
    |> Repo.one()
    |> case do
      %UsageCounter{} = counter -> {:ok, counter}
      nil -> {:error, :not_found}
    end
  end

  def get_usage_range(tenant_id, from_date, to_date) do
    UsageCounter
    |> where(
      [counter],
      counter.tenant_id == ^tenant_id and
        counter.metric_date >= ^from_date and
        counter.metric_date <= ^to_date
    )
    |> order_by([counter], asc: counter.metric_date)
    |> Repo.all()
  end

  def increment_usage_counter(tenant_id, metric_date, increments) do
    attrs =
      increments
      |> Map.new()
      |> Map.take([
        :messages_sent,
        :messages_received,
        :templates_sent,
        :active_contacts,
        :provider_cost_cents
      ])

    current =
      case get_usage_for_date(tenant_id, metric_date) do
        {:ok, counter} -> counter
        {:error, :not_found} -> %UsageCounter{tenant_id: tenant_id, metric_date: metric_date}
      end

    merged_attrs =
      Enum.reduce(attrs, %{tenant_id: tenant_id, metric_date: metric_date}, fn {field, increment},
                                                                               acc ->
        current_value = Map.get(current, field, 0) || 0
        Map.put(acc, field, current_value + increment)
      end)

    case current.id do
      nil -> %UsageCounter{} |> UsageCounter.changeset(merged_attrs) |> Repo.insert()
      _id -> current |> UsageCounter.changeset(merged_attrs) |> Repo.update()
    end
  end

  def tenant_plan_allows?(tenant_or_plan, capability, current_value \\ nil)

  def tenant_plan_allows?(%{plan: plan}, capability, current_value),
    do: tenant_plan_allows?(plan, capability, current_value)

  def tenant_plan_allows?(plan, capability, current_value) when is_binary(plan) do
    limits = Map.get(@plan_limits, plan, @plan_limits["starter"])

    case capability do
      :campaign_access -> Map.get(limits, :campaigns, false)
      :campaigns -> Map.get(limits, :campaigns, false)
      :whatsapp_accounts -> compare_limit(limits.whatsapp_accounts, current_value)
      :users -> compare_limit(limits.users, current_value)
      _ -> false
    end
  end

  defp compare_limit(limit, current_value) when is_integer(current_value),
    do: current_value < limit

  defp compare_limit(limit, nil), do: limit > 0
end
