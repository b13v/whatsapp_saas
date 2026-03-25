defmodule WhatsappSaas.Tenants do
  @moduledoc """
  Tenant/workspace domain operations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Audit.AuditLog
  alias WhatsappSaas.Repo
  alias WhatsappSaas.Tenants.Tenant

  @doc """
  Creates a tenant and optionally assigns the acting user as owner of it.
  """
  @spec create_tenant(struct() | nil, map()) ::
          {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def create_tenant(actor, attrs) do
    owner_user_id =
      Map.get(attrs, :owner_user_id) || Map.get(attrs, "owner_user_id") || actor_id(actor)

    if actor && actor.tenant_id do
      {:error, :already_assigned_to_tenant}
    else
      tenant_attrs =
        attrs
        |> Map.new()
        |> Map.put_new(:onboarding_status, "not_started")
        |> Map.put(:owner_user_id, owner_user_id)

      Multi.new()
      |> Multi.insert(:tenant, Tenant.changeset(%Tenant{}, tenant_attrs))
      |> maybe_attach_owner(actor)
      |> Multi.insert(:audit_log, fn %{tenant: tenant} ->
        AuditLog.changeset(%AuditLog{}, %{
          tenant_id: tenant.id,
          actor_user_id: actor_id(actor),
          action: "tenant_created",
          entity_type: "tenant",
          entity_id: tenant.id,
          payload: %{name: tenant.name, slug: tenant.slug}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{tenant: tenant}} -> {:ok, tenant}
        {:error, :tenant, changeset, _changes} -> {:error, changeset}
        {:error, :owner_user, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Updates safe tenant settings when the actor has owner/admin access.
  """
  @spec update_tenant(struct(), Tenant.t(), map()) ::
          {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def update_tenant(actor, %Tenant{} = tenant, attrs) do
    with :ok <- Policy.authorize_role_in_tenant(actor, tenant.id, ~w(owner admin)) do
      Multi.new()
      |> Multi.update(:tenant, Tenant.changeset(tenant, attrs))
      |> Multi.insert(:audit_log, fn %{tenant: updated_tenant} ->
        AuditLog.changeset(%AuditLog{}, %{
          tenant_id: updated_tenant.id,
          actor_user_id: actor.id,
          action: "tenant_updated",
          entity_type: "tenant",
          entity_id: updated_tenant.id,
          payload:
            Map.take(attrs, [:name, :slug, :status, :plan, :vertical, :timezone, :billing_email])
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{tenant: updated_tenant}} -> {:ok, updated_tenant}
        {:error, :tenant, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec get_tenant(struct(), Ecto.UUID.t()) :: {:ok, Tenant.t()} | {:error, atom()}
  def get_tenant(actor, tenant_id) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id),
         %Tenant{} = tenant <- Repo.get(Tenant, tenant_id) do
      {:ok, tenant}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_tenant!(struct(), Ecto.UUID.t()) :: Tenant.t()
  def get_tenant!(actor, tenant_id) do
    case get_tenant(actor, tenant_id) do
      {:ok, tenant} -> tenant
      _ -> raise Ecto.NoResultsError, queryable: Tenant
    end
  end

  @spec list_accessible_tenants(struct()) :: [Tenant.t()]
  def list_accessible_tenants(%User{tenant_id: nil}), do: []

  def list_accessible_tenants(%User{tenant_id: tenant_id}) do
    Tenant
    |> where([tenant], tenant.id == ^tenant_id)
    |> Repo.all()
  end

  @doc """
  Sets the onboarding status for a tenant when the actor can manage onboarding.
  """
  @spec set_onboarding_status(struct() | nil, Tenant.t() | Ecto.UUID.t(), String.t()) ::
          {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def set_onboarding_status(actor, %Tenant{} = tenant, status),
    do: do_set_onboarding_status(actor, tenant, status)

  def set_onboarding_status(actor, tenant_id, status) when is_binary(tenant_id) do
    with %Tenant{} = tenant <- Repo.get(Tenant, tenant_id) do
      do_set_onboarding_status(actor, tenant, status)
    else
      nil -> {:error, :not_found}
    end
  end

  defp do_set_onboarding_status(actor, tenant, status) do
    with :ok <- authorize_onboarding_status_change(actor, tenant.id) do
      update_tenant(actor || synthetic_system_user(tenant.id), tenant, %{
        onboarding_status: status
      })
    end
  end

  defp authorize_onboarding_status_change(nil, _tenant_id), do: :ok

  defp authorize_onboarding_status_change(actor, tenant_id),
    do: Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin))

  defp maybe_attach_owner(multi, nil), do: multi

  defp maybe_attach_owner(multi, %User{} = actor) do
    Multi.run(multi, :owner_user, fn repo, %{tenant: tenant} ->
      actor
      |> User.changeset(%{tenant_id: tenant.id, role: "owner", status: actor.status || "active"})
      |> repo.update()
    end)
  end

  defp actor_id(%User{id: id}), do: id
  defp actor_id(_), do: nil

  defp synthetic_system_user(tenant_id),
    do: %User{tenant_id: tenant_id, role: "owner", status: "active"}
end
