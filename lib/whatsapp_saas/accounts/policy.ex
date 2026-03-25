defmodule WhatsappSaas.Accounts.Policy do
  @moduledoc """
  Explicit tenant access and role authorization helpers.
  """

  alias WhatsappSaas.Accounts.User

  @role_order %{
    "viewer" => 0,
    "agent" => 1,
    "admin" => 2,
    "owner" => 3
  }

  @type authorization_error :: :unauthorized | :forbidden

  @spec authorize_tenant_access(struct() | nil, Ecto.UUID.t()) ::
          :ok | {:error, authorization_error()}
  def authorize_tenant_access(%User{tenant_id: tenant_id, status: "disabled"}, tenant_id),
    do: {:error, :forbidden}

  def authorize_tenant_access(%User{tenant_id: tenant_id}, tenant_id) when is_binary(tenant_id),
    do: :ok

  def authorize_tenant_access(%User{}, _tenant_id), do: {:error, :unauthorized}
  def authorize_tenant_access(nil, _tenant_id), do: {:error, :unauthorized}

  @spec authorize_role_in_tenant(struct() | nil, Ecto.UUID.t(), [String.t()]) ::
          :ok | {:error, authorization_error()}
  def authorize_role_in_tenant(user, tenant_id, allowed_roles) do
    with :ok <- authorize_tenant_access(user, tenant_id),
         true <- user.role in allowed_roles do
      :ok
    else
      false -> {:error, :forbidden}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec can_view_tenant?(struct() | nil, Ecto.UUID.t()) :: boolean()
  def can_view_tenant?(user, tenant_id), do: authorize_tenant_access(user, tenant_id) == :ok

  @spec can_manage_onboarding?(struct() | nil, Ecto.UUID.t()) :: boolean()
  def can_manage_onboarding?(user, tenant_id),
    do: authorize_role_in_tenant(user, tenant_id, ~w(owner admin)) == :ok

  @spec can_manage_campaigns?(struct() | nil, Ecto.UUID.t()) :: boolean()
  def can_manage_campaigns?(user, tenant_id),
    do: authorize_role_in_tenant(user, tenant_id, ~w(owner admin)) == :ok

  @spec can_manage_conversations?(struct() | nil, Ecto.UUID.t()) :: boolean()
  def can_manage_conversations?(user, tenant_id),
    do: authorize_role_in_tenant(user, tenant_id, ~w(owner admin agent)) == :ok

  @spec role_at_least?(String.t(), String.t()) :: boolean()
  def role_at_least?(role, minimum_role) do
    Map.get(@role_order, role, -1) >= Map.get(@role_order, minimum_role, 999)
  end
end
