defmodule WhatsappSaas.Onboarding do
  @moduledoc """
  Domain orchestration for tenant WhatsApp onboarding.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Audit
  alias WhatsappSaas.Billing
  alias WhatsappSaas.Onboarding.{OnboardingSession, SessionManager, StateMachine}
  alias WhatsappSaas.Repo
  alias WhatsappSaas.WhatsApp

  @managed_roles ~w(owner admin)

  @doc """
  Creates or reuses an active onboarding session for a tenant/provider pair.
  """
  def create_session_for_tenant(actor, attrs) do
    tenant_id = fetch_tenant_id!(attrs)
    provider = fetch_provider(attrs)

    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, @managed_roles),
         {:ok, _provider_module} <- normalize_provider_result(WhatsApp.provider_module(provider)) do
      case SessionManager.find_active_session_for_tenant(tenant_id, provider) do
        {:ok, %OnboardingSession{} = session} ->
          {:ok, %{session: session, setup_link: session.setup_link}}

        {:error, :session_not_found} ->
          with :ok <- check_whatsapp_account_plan_limit(tenant_id) do
            do_create_session(actor, tenant_id, provider, attrs)
          end
      end
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

  @doc """
  Marks redirect callback receipt without declaring the onboarding successful.
  """
  def mark_callback_received(callback_params, actor_or_nil \\ nil) do
    with {:ok, %OnboardingSession{} = session} <-
           SessionManager.find_session_by_callback_params(callback_params) do
      metadata =
        Map.merge(session.metadata || %{}, %{
          callback_params: Map.new(callback_params),
          callback_received_at: DateTime.utc_now()
        })

      target_state = callback_target_state(session.state)

      Multi.new()
      |> update_session_state(
        :session,
        session,
        target_state,
        %{
          metadata: metadata,
          external_setup_id:
            fetch_non_nil(callback_params, [
              :external_setup_id,
              "external_setup_id",
              :setup_id,
              "setup_id"
            ])
        }
      )
      |> Multi.run(:audit_log, fn _repo, %{session: updated_session} ->
        Audit.log(
          updated_session.tenant_id,
          actor_id(actor_or_nil),
          "onboarding_callback_received",
          "onboarding_session",
          updated_session.id,
          %{
            provider: updated_session.provider,
            external_setup_id: updated_session.external_setup_id,
            previous_state: session.state,
            new_state: updated_session.state
          }
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{session: updated_session}} -> {:ok, updated_session}
        {:error, :session, reason, _changes} -> {:error, reason}
        {:error, :audit_log, reason, _changes} -> {:error, reason}
      end
    else
      {:error, :session_not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reconciles provider-confirmed data into the local onboarding session and
  finalizes the connection only when enough account identifiers are present.
  """
  def reconcile_session_from_provider_data(%OnboardingSession{} = session, provider_payload) do
    attrs =
      provider_payload
      |> Map.new()
      |> Map.take([:external_setup_id, :setup_link, :expires_at])
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    metadata =
      Map.merge(session.metadata || %{}, %{
        provider_payload: provider_payload,
        reconciled_at: DateTime.utc_now()
      })

    next_state = reconciliation_state(session.state, provider_payload)

    Multi.new()
    |> update_session_state(:session, session, next_state, Map.put(attrs, :metadata, metadata))
    |> Multi.run(:audit_log, fn _repo, %{session: updated_session} ->
      Audit.log(
        updated_session.tenant_id,
        nil,
        "onboarding_reconciled",
        "onboarding_session",
        updated_session.id,
        %{
          provider: updated_session.provider,
          external_setup_id: updated_session.external_setup_id,
          previous_state: session.state,
          new_state: updated_session.state,
          whatsapp_account_id: updated_session.whatsapp_account_id
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: updated_session}} ->
        maybe_finalize(updated_session, provider_payload)

      {:error, :session, reason, _changes} ->
        {:error, reason}

      {:error, :audit_log, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Finalizes a provider-confirmed onboarding session into a connected account.
  """
  def finalize_connection(%OnboardingSession{} = session, normalized_account_data) do
    if finalizable_account_data?(normalized_account_data) do
      Multi.new()
      |> Multi.run(:account, fn _repo, _changes ->
        WhatsApp.upsert_account_from_provider(session.tenant_id, normalized_account_data)
      end)
      |> Multi.run(:connected_account, fn _repo, %{account: account} ->
        WhatsApp.mark_account_connected(account, normalized_account_data)
      end)
      |> update_session_state(:session, session, "connected", fn %{connected_account: account} ->
        %{
          whatsapp_account_id: account.id,
          completed_at: connected_at_value(normalized_account_data),
          metadata:
            Map.merge(session.metadata || %{}, %{
              finalized: true,
              finalized_at: DateTime.utc_now(),
              finalized_account_data: normalized_account_data
            })
        }
      end)
      |> Multi.run(:tenant, fn repo, _changes ->
        SessionManager.recompute_tenant_onboarding_status(repo, session.tenant_id)
      end)
      |> Multi.run(:audit_log, fn _repo,
                                  %{connected_account: account, session: updated_session} ->
        Audit.log(
          session.tenant_id,
          nil,
          "onboarding_finalized",
          "onboarding_session",
          updated_session.id,
          %{
            provider: updated_session.provider,
            external_setup_id: updated_session.external_setup_id,
            whatsapp_account_id: account.id,
            external_account_id: account.external_account_id,
            previous_state: session.state,
            new_state: updated_session.state
          }
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{connected_account: account, session: updated_session}} ->
          {:ok, %{session: updated_session, account: account}}

        {:error, :account, reason, _changes} ->
          {:error, reason}

        {:error, :connected_account, reason, _changes} ->
          {:error, reason}

        {:error, :session, reason, _changes} ->
          {:error, reason}

        {:error, :tenant, reason, _changes} ->
          {:error, reason}

        {:error, :audit_log, reason, _changes} ->
          {:error, reason}
      end
    else
      {:error, {:provider_error, :incomplete_account_data}}
    end
  end

  @doc """
  Marks a session as failed and recomputes tenant onboarding status safely.
  """
  def fail_session(%OnboardingSession{} = session, error_code, error_message) do
    Multi.new()
    |> update_session_state(
      :session,
      session,
      "failed",
      %{
        error_code: error_code,
        error_message: error_message,
        metadata:
          Map.merge(session.metadata || %{}, %{
            failed_at: DateTime.utc_now()
          })
      }
    )
    |> Multi.run(:tenant, fn repo, _changes ->
      SessionManager.recompute_tenant_onboarding_status(repo, session.tenant_id)
    end)
    |> Multi.run(:audit_log, fn _repo, %{session: updated_session} ->
      Audit.log(
        session.tenant_id,
        nil,
        "onboarding_failed",
        "onboarding_session",
        updated_session.id,
        %{
          provider: updated_session.provider,
          external_setup_id: updated_session.external_setup_id,
          previous_state: session.state,
          new_state: updated_session.state,
          error_code: error_code,
          error_message: error_message
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: updated_session}} -> {:ok, updated_session}
      {:error, :session, reason, _changes} -> {:error, reason}
      {:error, :tenant, reason, _changes} -> {:error, reason}
      {:error, :audit_log, reason, _changes} -> {:error, reason}
    end
  end

  defp do_create_session(actor, tenant_id, provider, attrs) do
    with {:ok, provider_module} <- WhatsApp.provider_module(provider),
         {:ok, provider_data} <-
           normalize_provider_error(provider_module.create_onboarding_session(Map.new(attrs))) do
      session_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      session_attrs =
        attrs
        |> Map.new()
        |> Map.put(:id, session_id)
        |> Map.put(:tenant_id, tenant_id)
        |> Map.put(:provider, provider)
        |> Map.put(:state, "link_generated")
        |> Map.put(:external_setup_id, provider_data.external_setup_id)
        |> Map.put(:setup_link, provider_data.setup_link)
        |> Map.put(
          :redirect_url,
          provider_data.redirect_url || Map.get(attrs, :redirect_url) ||
            Map.get(attrs, "redirect_url")
        )
        |> Map.put(:expires_at, provider_data.expires_at)
        |> Map.put(
          :metadata,
          Map.merge(provider_data.metadata || %{}, %{
            onboarding_mode:
              Map.get(attrs, :onboarding_mode) || Map.get(attrs, "onboarding_mode"),
            requested_at: now
          })
        )

      Multi.new()
      |> supersede_existing_active_session(tenant_id, provider, session_id)
      |> Multi.insert(:session, OnboardingSession.changeset(%OnboardingSession{}, session_attrs))
      |> Multi.run(:tenant, fn repo, _changes ->
        SessionManager.recompute_tenant_onboarding_status(repo, tenant_id)
      end)
      |> Multi.run(:audit_log, fn _repo, %{session: session} ->
        Audit.log(
          tenant_id,
          actor.id,
          "onboarding_session_created",
          "onboarding_session",
          session.id,
          %{
            provider: provider,
            external_setup_id: session.external_setup_id,
            previous_state: nil,
            new_state: session.state
          }
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{session: session}} -> {:ok, %{session: session, setup_link: session.setup_link}}
        {:error, :session, reason, _changes} -> {:error, reason}
        {:error, :superseded_session, reason, _changes} -> {:error, reason}
        {:error, :tenant, reason, _changes} -> {:error, reason}
        {:error, :audit_log, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp supersede_existing_active_session(multi, tenant_id, provider, new_session_id) do
    Multi.run(multi, :superseded_session, fn repo, _changes ->
      case SessionManager.find_active_session_for_tenant(tenant_id, provider) do
        {:ok, %OnboardingSession{} = session} ->
          session
          |> OnboardingSession.changeset(%{
            metadata: SessionManager.supersede_metadata(session, new_session_id)
          })
          |> repo.update()

        {:error, :session_not_found} ->
          {:ok, nil}
      end
    end)
  end

  defp maybe_finalize(%OnboardingSession{} = session, provider_payload) do
    if finalizable_account_data?(provider_payload) do
      finalize_connection(session, provider_payload)
    else
      {:ok, session}
    end
  end

  defp update_session_state(
         multi,
         name,
         %OnboardingSession{} = session,
         target_state,
         attrs_or_fun
       ) do
    Multi.run(multi, name, fn repo, changes ->
      with {:ok, next_state} <- StateMachine.transition(session.state, target_state) do
        dynamic_attrs =
          case attrs_or_fun do
            fun when is_function(fun, 1) -> fun.(changes)
            attrs -> attrs
          end

        attrs =
          dynamic_attrs
          |> Map.new()
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
          |> Map.put(:state, next_state)

        session
        |> OnboardingSession.changeset(attrs)
        |> repo.update()
      end
    end)
  end

  defp callback_target_state("connected"), do: "connected"
  defp callback_target_state("failed"), do: "failed"
  defp callback_target_state(_state), do: "callback_received"

  defp reconciliation_state(current_state, provider_payload) do
    provider_state =
      Map.get(provider_payload, :state) || Map.get(provider_payload, "state")

    cond do
      finalizable_account_data?(provider_payload) -> "connected"
      provider_state in ["callback_received", "pending", "processing"] -> "callback_received"
      current_state == "created" -> "link_generated"
      true -> current_state
    end
  end

  defp finalizable_account_data?(attrs) when is_map(attrs) do
    value = Map.get(attrs, :external_account_id) || Map.get(attrs, "external_account_id")
    is_binary(value) and value != ""
  end

  defp check_whatsapp_account_plan_limit(tenant_id) do
    tenant = Repo.get!(WhatsappSaas.Tenants.Tenant, tenant_id)

    account_count =
      WhatsappSaas.WhatsApp.WhatsappAccount
      |> where([account], account.tenant_id == ^tenant_id)
      |> Repo.aggregate(:count, :id)

    if Billing.tenant_plan_allows?(tenant, :whatsapp_accounts, account_count) do
      :ok
    else
      {:error, :plan_limit_reached}
    end
  end

  defp connected_at_value(attrs) do
    Map.get(attrs, :connected_at) || Map.get(attrs, "connected_at") || DateTime.utc_now()
  end

  defp fetch_tenant_id!(attrs) do
    Map.get(attrs, :tenant_id) || Map.fetch!(attrs, "tenant_id")
  end

  defp fetch_provider(attrs) do
    Map.get(attrs, :provider) || Map.get(attrs, "provider") || "kapso"
  end

  defp fetch_non_nil(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp normalize_provider_result({:ok, _module} = ok), do: ok
  defp normalize_provider_result({:error, :unknown_provider}), do: {:error, :unsupported_provider}
  defp normalize_provider_result(other), do: other

  defp normalize_provider_error({:error, reason}), do: {:error, {:provider_error, reason}}
  defp normalize_provider_error(other), do: other

  defp actor_id(%{id: id}), do: id
  defp actor_id(_), do: nil
end
