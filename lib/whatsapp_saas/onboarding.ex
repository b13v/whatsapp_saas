defmodule WhatsappSaas.Onboarding do
  @moduledoc """
  Domain logic for WhatsApp onboarding sessions.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Onboarding.OnboardingSession
  alias WhatsappSaas.Repo
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp

  @doc """
  Creates an onboarding session for a tenant via the configured provider boundary.
  """
  def create_session_for_tenant(actor, attrs) do
    tenant_id = fetch_tenant_id!(attrs)
    provider = Map.get(attrs, :provider) || Map.get(attrs, "provider") || "kapso"

    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)),
         {:ok, provider_module} <- WhatsApp.provider_module(provider),
         {:ok, provider_data} <- provider_module.create_onboarding_session(Map.new(attrs)) do
      session_attrs =
        attrs
        |> Map.new()
        |> Map.put(:tenant_id, tenant_id)
        |> Map.put(:provider, provider)
        |> Map.put(:external_setup_id, provider_data.external_setup_id)
        |> Map.put(:setup_link, provider_data.setup_link)
        |> Map.put(:expires_at, provider_data.expires_at)
        |> Map.put(:metadata, provider_data.metadata || %{})

      Multi.new()
      |> Multi.update(
        :tenant,
        Tenant.changeset(Repo.get!(Tenant, tenant_id), %{onboarding_status: "in_progress"})
      )
      |> Multi.insert(:session, OnboardingSession.changeset(%OnboardingSession{}, session_attrs))
      |> Multi.insert(:audit_log, fn %{session: session} ->
        WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
          tenant_id: tenant_id,
          actor_user_id: actor.id,
          action: "onboarding_session_created",
          entity_type: "onboarding_session",
          entity_id: session.id,
          payload: %{provider: provider, setup_link: session.setup_link}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{session: session}} -> {:ok, %{session: session, setup_link: session.setup_link}}
        {:error, :session, changeset, _changes} -> {:error, changeset}
        {:error, :tenant, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_session(actor, session_id) do
    case Repo.get(OnboardingSession, session_id) do
      %OnboardingSession{} = session ->
        with :ok <- Policy.authorize_tenant_access(actor, session.tenant_id) do
          {:ok, session}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def get_session!(actor, session_id) do
    case get_session(actor, session_id) do
      {:ok, session} -> session
      _ -> raise Ecto.NoResultsError, queryable: OnboardingSession
    end
  end

  def list_sessions_for_tenant(actor, tenant_id) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      OnboardingSession
      |> where([session], session.tenant_id == ^tenant_id)
      |> order_by([session], desc: session.inserted_at)
      |> Repo.all()
    end
  end

  def mark_callback_received(callback_params, actor_or_nil \\ nil) do
    external_setup_id =
      Map.get(callback_params, :external_setup_id) ||
        Map.get(callback_params, "external_setup_id") ||
        Map.get(callback_params, :setup_id) ||
        Map.get(callback_params, "setup_id")

    case Repo.get_by(OnboardingSession, external_setup_id: external_setup_id) do
      %OnboardingSession{} = session ->
        metadata =
          Map.merge(session.metadata || %{}, %{
            callback_params: callback_params,
            callback_received_at: DateTime.utc_now()
          })

        Multi.new()
        |> Multi.update(
          :session,
          OnboardingSession.changeset(session, %{state: "callback_received", metadata: metadata})
        )
        |> Multi.insert(:audit_log, fn %{session: updated_session} ->
          WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
            tenant_id: updated_session.tenant_id,
            actor_user_id: actor_id(actor_or_nil),
            action: "onboarding_callback_received",
            entity_type: "onboarding_session",
            entity_id: updated_session.id,
            payload: %{external_setup_id: updated_session.external_setup_id}
          })
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{session: updated_session}} -> {:ok, updated_session}
          {:error, :session, changeset, _changes} -> {:error, changeset}
          {:error, _step, reason, _changes} -> {:error, reason}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def reconcile_session_from_provider_data(%OnboardingSession{} = session, provider_payload) do
    attrs =
      provider_payload
      |> Map.new()
      |> Map.take([:external_setup_id, :setup_link, :state, :expires_at, :metadata])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    session
    |> OnboardingSession.changeset(attrs)
    |> Repo.update()
  end

  def finalize_connection(%OnboardingSession{} = session, normalized_account_data) do
    Multi.new()
    |> Multi.run(:account, fn _repo, _changes ->
      WhatsApp.upsert_account_from_provider(session.tenant_id, normalized_account_data)
    end)
    |> Multi.run(:connected_account, fn _repo, %{account: account} ->
      WhatsApp.mark_account_connected(account, normalized_account_data)
    end)
    |> Multi.run(:session, fn repo, %{connected_account: account} ->
      session
      |> OnboardingSession.changeset(%{
        whatsapp_account_id: account.id,
        state: "completed",
        completed_at: DateTime.utc_now(),
        metadata: Map.merge(session.metadata || %{}, %{finalized: true})
      })
      |> repo.update()
    end)
    |> Multi.run(:tenant, fn repo, _changes ->
      tenant = repo.get!(Tenant, session.tenant_id)

      tenant
      |> Tenant.changeset(%{onboarding_status: "connected"})
      |> repo.update()
    end)
    |> Multi.insert(:audit_log, fn %{connected_account: account} ->
      WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
        tenant_id: session.tenant_id,
        actor_user_id: nil,
        action: "onboarding_finalized",
        entity_type: "onboarding_session",
        entity_id: session.id,
        payload: %{
          whatsapp_account_id: account.id,
          external_account_id: account.external_account_id
        }
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{connected_account: account, session: updated_session}} ->
        {:ok, %{session: updated_session, account: account}}

      {:error, :session, changeset, _changes} ->
        {:error, changeset}

      {:error, :tenant, changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  def fail_session(%OnboardingSession{} = session, error_code, error_message) do
    Multi.new()
    |> Multi.update(
      :session,
      OnboardingSession.changeset(session, %{
        state: "failed",
        error_code: error_code,
        error_message: error_message
      })
    )
    |> Multi.run(:tenant, fn repo, _changes ->
      tenant = repo.get!(Tenant, session.tenant_id)

      tenant
      |> Tenant.changeset(%{onboarding_status: "failed"})
      |> repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: updated_session}} -> {:ok, updated_session}
      {:error, :session, changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp fetch_tenant_id!(attrs) do
    Map.get(attrs, :tenant_id) || Map.fetch!(attrs, "tenant_id")
  end

  defp actor_id(%{id: id}), do: id
  defp actor_id(_), do: nil
end
