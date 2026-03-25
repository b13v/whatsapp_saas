defmodule WhatsappSaas.Audit do
  @moduledoc """
  Append-only audit log access for important tenant actions.
  """

  import Ecto.Query, warn: false

  alias WhatsappSaas.Audit.AuditLog
  alias WhatsappSaas.Repo

  @spec log(Ecto.UUID.t(), Ecto.UUID.t() | nil, String.t(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def log(tenant_id, actor_user_id, action, entity_type, entity_id, payload \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      tenant_id: tenant_id,
      actor_user_id: actor_user_id,
      action: action,
      entity_type: entity_type,
      entity_id: entity_id,
      payload: payload
    })
    |> Repo.insert()
  end

  @spec list_tenant_audit_logs(Ecto.UUID.t(), keyword()) :: [struct()]
  def list_tenant_audit_logs(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> where([audit_log], audit_log.tenant_id == ^tenant_id)
    |> order_by([audit_log], desc: audit_log.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
