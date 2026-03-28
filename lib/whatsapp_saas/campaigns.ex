defmodule WhatsappSaas.Campaigns do
  @moduledoc """
  Campaign lifecycle and audience selection domain logic.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Campaigns.{Campaign, CampaignDelivery}
  alias WhatsappSaas.Contacts
  alias WhatsappSaas.Repo
  alias WhatsappSaas.WhatsApp.Template

  def list_campaigns(actor, tenant_id, opts \\ []) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      Campaign
      |> where([campaign], campaign.tenant_id == ^tenant_id)
      |> order_by([campaign], desc: campaign.inserted_at)
      |> paginate(opts)
      |> Repo.all()
    end
  end

  def get_campaign(actor, campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      %Campaign{} = campaign ->
        with :ok <- Policy.authorize_tenant_access(actor, campaign.tenant_id), do: {:ok, campaign}

      nil ->
        {:error, :not_found}
    end
  end

  def get_campaign!(actor, campaign_id) do
    case get_campaign(actor, campaign_id) do
      {:ok, campaign} -> campaign
      _ -> raise Ecto.NoResultsError, queryable: Campaign
    end
  end

  def create_campaign(actor, attrs) do
    tenant_id = fetch_tenant_id!(attrs)
    template_id = Map.get(attrs, :template_id) || Map.get(attrs, "template_id")

    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)),
         %Template{tenant_id: ^tenant_id} <- Repo.get(Template, template_id) do
      Multi.new()
      |> Multi.insert(:campaign, Campaign.changeset(%Campaign{}, attrs))
      |> Multi.insert(:audit_log, fn %{campaign: campaign} ->
        WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
          tenant_id: campaign.tenant_id,
          actor_user_id: actor.id,
          action: "campaign_created",
          entity_type: "campaign",
          entity_id: campaign.id,
          payload: %{name: campaign.name, template_id: campaign.template_id}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{campaign: campaign}} -> {:ok, campaign}
        {:error, :campaign, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      nil -> {:error, :template_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :template_tenant_mismatch}
    end
  end

  def update_campaign(actor, %Campaign{} = campaign, attrs) do
    with :ok <- Policy.authorize_role_in_tenant(actor, campaign.tenant_id, ~w(owner admin)) do
      campaign
      |> Campaign.changeset(attrs)
      |> Repo.update()
    end
  end

  def schedule_campaign(actor, %Campaign{} = campaign, scheduled_at) do
    with :ok <- Policy.authorize_role_in_tenant(actor, campaign.tenant_id, ~w(owner admin)) do
      Multi.new()
      |> Multi.update(
        :campaign,
        Campaign.changeset(campaign, %{status: "scheduled", scheduled_at: scheduled_at})
      )
      |> Multi.insert(:audit_log, fn %{campaign: updated_campaign} ->
        WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
          tenant_id: updated_campaign.tenant_id,
          actor_user_id: actor.id,
          action: "campaign_scheduled",
          entity_type: "campaign",
          entity_id: updated_campaign.id,
          payload: %{scheduled_at: updated_campaign.scheduled_at, enqueue_worker: false}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{campaign: updated_campaign}} -> {:ok, updated_campaign}
        {:error, :campaign, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  def cancel_campaign(actor, %Campaign{} = campaign) do
    with :ok <- Policy.authorize_role_in_tenant(actor, campaign.tenant_id, ~w(owner admin)),
         false <- campaign.status == "completed" do
      Multi.new()
      |> Multi.update(:campaign, Campaign.changeset(campaign, %{status: "cancelled"}))
      |> Multi.insert(:audit_log, fn %{campaign: updated_campaign} ->
        WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
          tenant_id: updated_campaign.tenant_id,
          actor_user_id: actor.id,
          action: "campaign_cancelled",
          entity_type: "campaign",
          entity_id: updated_campaign.id,
          payload: %{status: updated_campaign.status}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{campaign: updated_campaign}} -> {:ok, updated_campaign}
        {:error, :campaign, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      true -> {:error, :campaign_completed}
      {:error, reason} -> {:error, reason}
    end
  end

  def build_campaign_audience(actor, %Campaign{} = campaign) do
    with :ok <- Policy.authorize_tenant_access(actor, campaign.tenant_id) do
      audience_filter = campaign.audience_filter || %{}
      mode = Map.get(audience_filter, "mode") || Map.get(audience_filter, :mode) || "all_contacts"

      Contacts.list_contacts_for_audience(campaign.tenant_id, mode)
    end
  end

  def create_campaign_deliveries(actor, %Campaign{} = campaign) do
    with :ok <- Policy.authorize_role_in_tenant(actor, campaign.tenant_id, ~w(owner admin)),
         {:ok, contacts} <- build_campaign_audience(actor, campaign) do
      Multi.new()
      |> Multi.run(:deliveries, fn repo, _changes ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        records =
          Enum.map(contacts, fn contact ->
            %{
              id: Ecto.UUID.generate(),
              tenant_id: campaign.tenant_id,
              campaign_id: campaign.id,
              contact_id: contact.id,
              status: "queued",
              inserted_at: now,
              updated_at: now
            }
          end)

        {count, _} =
          repo.insert_all(CampaignDelivery, records,
            on_conflict: :nothing,
            conflict_target: [:campaign_id, :contact_id]
          )

        {:ok, count}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{deliveries: deliveries}} -> {:ok, deliveries}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp fetch_tenant_id!(attrs) do
    Map.get(attrs, :tenant_id) || Map.fetch!(attrs, "tenant_id")
  end

  @default_page_size 50

  defp paginate(query, opts) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end
end
