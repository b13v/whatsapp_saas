defmodule WhatsappSaas.Accounts do
  @moduledoc """
  Tenant-user and role-aware account operations.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.{Policy, User}
  alias WhatsappSaas.Audit.AuditLog
  alias WhatsappSaas.Repo
  alias WhatsappSaas.Tenants.Tenant

  @spec get_user!(Ecto.UUID.t()) :: User.t()
  def get_user!(user_id), do: Repo.get!(User, user_id)

  @spec get_user_in_tenant(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_in_tenant(tenant_id, user_id) do
    User
    |> where([user], user.id == ^user_id and user.tenant_id == ^tenant_id)
    |> Repo.one()
    |> case do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  @spec list_tenant_users(struct(), Ecto.UUID.t()) :: [User.t()] | {:error, atom()}
  def list_tenant_users(actor, tenant_id) do
    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)) do
      User
      |> where([user], user.tenant_id == ^tenant_id)
      |> order_by([user], asc: user.inserted_at)
      |> Repo.all()
    end
  end

  @doc """
  Creates a tenant-scoped invited user without delivering email yet.
  """
  @spec invite_user_to_tenant(struct(), Tenant.t() | Ecto.UUID.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def invite_user_to_tenant(actor, %Tenant{id: tenant_id}, attrs),
    do: invite_user_to_tenant(actor, tenant_id, attrs)

  def invite_user_to_tenant(actor, tenant_id, attrs) do
    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)) do
      user_attrs =
        attrs
        |> Map.new()
        |> Map.put(:tenant_id, tenant_id)
        |> Map.put_new(:role, "agent")
        |> Map.put(:status, "invited")
        |> Map.put_new(:hashed_password, placeholder_password_hash())

      Multi.new()
      |> Multi.insert(:user, User.changeset(%User{}, user_attrs))
      |> Multi.insert(:audit_log, fn %{user: user} ->
        AuditLog.changeset(%AuditLog{}, %{
          tenant_id: tenant_id,
          actor_user_id: actor.id,
          action: "user_invited",
          entity_type: "user",
          entity_id: user.id,
          payload: %{email: user.email, role: user.role}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, :user, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @spec update_user_role(struct(), User.t() | Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def update_user_role(actor, %User{} = user, tenant_id, role),
    do: do_update_user_role(actor, user, tenant_id, role)

  def update_user_role(actor, user_id, tenant_id, role) when is_binary(user_id) do
    with {:ok, user} <- get_user_in_tenant(tenant_id, user_id) do
      do_update_user_role(actor, user, tenant_id, role)
    end
  end

  @spec disable_user(struct(), User.t() | Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()} | {:error, atom()}
  def disable_user(actor, %User{} = user, tenant_id), do: do_disable_user(actor, user, tenant_id)

  def disable_user(actor, user_id, tenant_id) when is_binary(user_id) do
    with {:ok, user} <- get_user_in_tenant(tenant_id, user_id) do
      do_disable_user(actor, user, tenant_id)
    end
  end

  @spec user_has_tenant_access?(struct() | nil, Ecto.UUID.t()) :: boolean()
  def user_has_tenant_access?(user, tenant_id), do: Policy.can_view_tenant?(user, tenant_id)

  @spec authorize_tenant_role(struct() | nil, Ecto.UUID.t(), [String.t()]) ::
          :ok | {:error, atom()}
  def authorize_tenant_role(user, tenant_id, allowed_roles),
    do: Policy.authorize_role_in_tenant(user, tenant_id, allowed_roles)

  def can_manage_onboarding?(user, tenant_id), do: Policy.can_manage_onboarding?(user, tenant_id)
  def can_manage_campaigns?(user, tenant_id), do: Policy.can_manage_campaigns?(user, tenant_id)

  def can_manage_conversations?(user, tenant_id),
    do: Policy.can_manage_conversations?(user, tenant_id)

  def can_view_tenant?(user, tenant_id), do: Policy.can_view_tenant?(user, tenant_id)

  defp do_update_user_role(actor, user, tenant_id, role) do
    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)),
         true <- user.tenant_id == tenant_id do
      Multi.new()
      |> Multi.update(:user, User.changeset(user, %{role: role}))
      |> Multi.insert(:audit_log, fn %{user: updated_user} ->
        AuditLog.changeset(%AuditLog{}, %{
          tenant_id: tenant_id,
          actor_user_id: actor.id,
          action: "user_role_updated",
          entity_type: "user",
          entity_id: updated_user.id,
          payload: %{role: updated_user.role}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: updated_user}} -> {:ok, updated_user}
        {:error, :user, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_disable_user(actor, user, tenant_id) do
    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)),
         true <- user.tenant_id == tenant_id do
      Multi.new()
      |> Multi.update(:user, User.changeset(user, %{status: "disabled"}))
      |> Multi.insert(:audit_log, fn %{user: disabled_user} ->
        AuditLog.changeset(%AuditLog{}, %{
          tenant_id: tenant_id,
          actor_user_id: actor.id,
          action: "user_disabled",
          entity_type: "user",
          entity_id: disabled_user.id,
          payload: %{status: disabled_user.status}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: disabled_user}} -> {:ok, disabled_user}
        {:error, :user, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp placeholder_password_hash do
    :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
  end
end
