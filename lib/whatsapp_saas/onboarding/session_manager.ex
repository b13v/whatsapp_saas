defmodule WhatsappSaas.Onboarding.SessionManager do
  @moduledoc """
  Helpers for onboarding session correlation, active-session reuse, and
  conservative tenant status recomputation.
  """

  import Ecto.Query, warn: false

  alias WhatsappSaas.Onboarding.OnboardingSession
  alias WhatsappSaas.Repo
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.WhatsappAccount

  @active_states ~w(created link_generated callback_received)

  @spec find_session_by_external_setup_id(String.t() | atom(), String.t() | nil) ::
          {:ok, OnboardingSession.t()} | {:error, :session_not_found}
  def find_session_by_external_setup_id(_provider, nil), do: {:error, :session_not_found}

  def find_session_by_external_setup_id(provider, external_setup_id) do
    OnboardingSession
    |> where(
      [session],
      session.provider == ^to_string(provider) and session.external_setup_id == ^external_setup_id
    )
    |> order_by([session], desc: session.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      %OnboardingSession{} = session -> {:ok, session}
      nil -> {:error, :session_not_found}
    end
  end

  @spec find_active_session_for_tenant(Ecto.UUID.t(), String.t() | atom()) ::
          {:ok, OnboardingSession.t()} | {:error, :session_not_found}
  def find_active_session_for_tenant(tenant_id, provider) do
    OnboardingSession
    |> where(
      [session],
      session.tenant_id == ^tenant_id and
        session.provider == ^to_string(provider) and
        session.state in ^@active_states
    )
    |> order_by([session], desc: session.inserted_at)
    |> Repo.all()
    |> Enum.find(&reusable?/1)
    |> case do
      %OnboardingSession{} = session -> {:ok, session}
      nil -> {:error, :session_not_found}
    end
  end

  @spec find_session_by_callback_params(map()) ::
          {:ok, OnboardingSession.t()} | {:error, :session_not_found}
  def find_session_by_callback_params(params) do
    provider = Map.get(params, :provider) || Map.get(params, "provider") || "kapso"

    with {:error, :session_not_found} <-
           find_session_by_external_setup_id(provider, external_setup_id(params)),
         {:error, :session_not_found} <- find_session_by_local_id(local_session_id(params)),
         {:error, :session_not_found} <- find_session_by_metadata_hints(provider, params) do
      {:error, :session_not_found}
    else
      {:ok, %OnboardingSession{} = session} -> {:ok, session}
    end
  end

  @spec reusable?(OnboardingSession.t()) :: boolean()
  def reusable?(%OnboardingSession{} = session) do
    session.state in @active_states and not expired?(session) and is_binary(session.setup_link)
  end

  @spec active_relevant?(OnboardingSession.t()) :: boolean()
  def active_relevant?(%OnboardingSession{} = session), do: session.state in @active_states

  @spec supersede_metadata(OnboardingSession.t(), Ecto.UUID.t()) :: map()
  def supersede_metadata(%OnboardingSession{} = session, new_session_id) do
    Map.merge(session.metadata || %{}, %{
      superseded: true,
      superseded_at: DateTime.utc_now(),
      superseded_by_session_id: new_session_id
    })
  end

  @spec recompute_tenant_onboarding_status(Ecto.Repo.t(), Ecto.UUID.t()) ::
          {:ok, Tenant.t()} | {:error, Ecto.Changeset.t()}
  def recompute_tenant_onboarding_status(repo, tenant_id) do
    tenant = repo.get!(Tenant, tenant_id)
    status = derive_tenant_onboarding_status(repo, tenant_id)

    tenant
    |> Tenant.changeset(%{onboarding_status: status})
    |> repo.update()
  end

  @spec derive_tenant_onboarding_status(Ecto.Repo.t(), Ecto.UUID.t()) :: String.t()
  def derive_tenant_onboarding_status(repo, tenant_id) do
    cond do
      connected_account_exists?(repo, tenant_id) -> "connected"
      active_session_exists?(repo, tenant_id) -> "in_progress"
      latest_failed_session?(repo, tenant_id) -> "failed"
      true -> "not_started"
    end
  end

  defp connected_account_exists?(repo, tenant_id) do
    WhatsappAccount
    |> where(
      [account],
      account.tenant_id == ^tenant_id and account.status == "connected"
    )
    |> repo.exists?()
  end

  defp active_session_exists?(repo, tenant_id) do
    OnboardingSession
    |> where([session], session.tenant_id == ^tenant_id and session.state in ^@active_states)
    |> repo.exists?()
  end

  defp latest_failed_session?(repo, tenant_id) do
    OnboardingSession
    |> where([session], session.tenant_id == ^tenant_id)
    |> order_by([session], desc: session.inserted_at)
    |> limit(1)
    |> repo.one()
    |> case do
      %OnboardingSession{state: "failed"} -> true
      _ -> false
    end
  end

  defp expired?(%OnboardingSession{expires_at: nil}), do: false

  defp expired?(%OnboardingSession{expires_at: expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) == :lt

  defp external_setup_id(params) do
    Map.get(params, :external_setup_id) ||
      Map.get(params, "external_setup_id") ||
      Map.get(params, :setup_id) ||
      Map.get(params, "setup_id")
  end

  defp local_session_id(params) do
    Map.get(params, :onboarding_session_id) ||
      Map.get(params, "onboarding_session_id") ||
      Map.get(params, :session_id) ||
      Map.get(params, "session_id")
  end

  defp find_session_by_local_id(nil), do: {:error, :session_not_found}

  defp find_session_by_local_id(session_id) do
    case Repo.get(OnboardingSession, session_id) do
      %OnboardingSession{} = session -> {:ok, session}
      nil -> {:error, :session_not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :session_not_found}
  end

  defp find_session_by_metadata_hints(provider, params) do
    tenant_id = Map.get(params, :tenant_id) || Map.get(params, "tenant_id")

    if is_binary(tenant_id) do
      find_active_session_for_tenant(tenant_id, provider)
    else
      {:error, :session_not_found}
    end
  end
end
