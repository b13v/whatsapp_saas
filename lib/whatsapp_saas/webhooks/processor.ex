defmodule WhatsappSaas.Webhooks.Processor do
  @moduledoc """
  Domain webhook event processing.
  """

  require Logger

  alias WhatsappSaas.Inbox
  alias WhatsappSaas.Onboarding
  alias WhatsappSaas.Onboarding.SessionManager
  alias WhatsappSaas.Webhooks.EventRouter
  alias WhatsappSaas.WhatsApp
  alias WhatsappSaas.WhatsApp.{Template, WebhookEvent}

  @spec process_normalized_event(WebhookEvent.t(), map()) :: {:ok, term()} | {:error, term()}
  def process_normalized_event(%WebhookEvent{} = webhook_event, normalized_event) do
    with {:ok, route} <- EventRouter.route(normalized_event) do
      case route do
        :account -> process_account_event(webhook_event, normalized_event)
        :template -> process_template_event(normalized_event)
        :message -> process_inbound_message_event(normalized_event)
        :message_status -> process_message_status_event(normalized_event)
      end
    end
  end

  defp process_account_event(_webhook_event, normalized_event) do
    provider = fetch(normalized_event, :provider)
    payload = fetch(normalized_event, :payload) || %{}
    account_data = get_in(normalized_event, [:normalized_data, :account]) || %{}

    external_setup_id =
      Map.get(payload, :external_setup_id) ||
        Map.get(payload, "external_setup_id") ||
        Map.get(payload, :setup_id) ||
        Map.get(payload, "setup_id")

    with {:ok, account_or_session} <-
           resolve_account_or_session(provider, external_setup_id, normalized_event, account_data) do
      case account_or_session do
        {:session, session} ->
          Onboarding.reconcile_session_from_provider_data(
            session,
            Map.put(account_data, :provider, provider)
          )

        {:account, account} ->
          apply_account_update(account, account_data)

        :unresolved ->
          Logger.warning("webhook account event unresolved")
          {:ok, :unresolved}
      end
    end
  end

  defp process_template_event(normalized_event) do
    with {:ok, account} <- resolve_account_from_event(normalized_event),
         template_data <- get_in(normalized_event, [:normalized_data, :template]) || %{},
         {:ok, %Template{} = template} <-
           WhatsApp.upsert_template(
             account.tenant_id,
             Map.merge(template_data, %{whatsapp_account_id: account.id})
           ) do
      {:ok, template}
    else
      {:error, :not_found} ->
        Logger.warning("webhook template event unresolved account")
        {:ok, :unresolved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_inbound_message_event(normalized_event) do
    with {:ok, account} <- resolve_account_from_event(normalized_event),
         normalized_payload <-
           Map.put(
             fetch(normalized_event, :normalized_data) || %{},
             :whatsapp_account_id,
             account.id
           ),
         {:ok, result} <- Inbox.record_inbound_message(account.tenant_id, normalized_payload) do
      {:ok, result}
    else
      {:error, :not_found} ->
        Logger.warning("webhook inbound message unresolved account")
        {:ok, :unresolved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_message_status_event(normalized_event) do
    normalized_data = fetch(normalized_event, :normalized_data) || %{}

    provider_message_id =
      Map.get(normalized_data, :provider_message_id) ||
        Map.get(normalized_data, "provider_message_id")

    with {:ok, message} <- Inbox.get_message_by_provider_message_id(provider_message_id),
         status <- Map.get(normalized_data, :status) || Map.get(normalized_data, "status"),
         attrs <- %{
           sent_at: Map.get(normalized_data, :sent_at) || Map.get(normalized_data, "sent_at"),
           delivered_at:
             Map.get(normalized_data, :delivered_at) || Map.get(normalized_data, "delivered_at"),
           read_at: Map.get(normalized_data, :read_at) || Map.get(normalized_data, "read_at"),
           failed_at:
             Map.get(normalized_data, :failed_at) || Map.get(normalized_data, "failed_at"),
           error_code:
             Map.get(normalized_data, :error_code) || Map.get(normalized_data, "error_code"),
           error_message:
             Map.get(normalized_data, :error_message) || Map.get(normalized_data, "error_message")
         },
         {:ok, updated_message} <- Inbox.apply_provider_message_status(message, status, attrs) do
      {:ok, updated_message}
    else
      {:error, :not_found} ->
        Logger.warning(
          "webhook message status unresolved provider_message_id=#{inspect(provider_message_id)}"
        )

        {:ok, :unresolved}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_account_or_session(provider, external_setup_id, normalized_event, account_data) do
    case SessionManager.find_session_by_external_setup_id(provider, external_setup_id) do
      {:ok, session} ->
        {:ok, {:session, session}}

      {:error, :session_not_found} ->
        case resolve_account_from_event(normalized_event) do
          {:ok, account} -> {:ok, {:account, account}}
          {:error, :not_found} -> resolve_active_session_from_account_data(provider, account_data)
        end
    end
  end

  defp resolve_active_session_from_account_data(provider, account_data) do
    with {:ok, account} <- WhatsApp.find_account_by_provider_hints(provider, account_data) do
      case SessionManager.find_active_session_for_tenant(account.tenant_id, provider) do
        {:ok, session} -> {:ok, {:session, session}}
        {:error, :session_not_found} -> {:ok, {:account, account}}
      end
    else
      {:error, :not_found} -> {:ok, :unresolved}
    end
  end

  defp resolve_account_from_event(normalized_event) do
    provider = fetch(normalized_event, :provider)
    account_hint = fetch(normalized_event, :account_hint) || %{}
    normalized_data = fetch(normalized_event, :normalized_data) || %{}

    hints =
      case Map.get(normalized_data, :account) || Map.get(normalized_data, "account") do
        account when is_map(account) -> Map.merge(account_hint, account)
        _ -> account_hint
      end

    WhatsApp.find_account_by_provider_hints(provider, hints)
  end

  defp apply_account_update(account, account_data) do
    with {:ok, updated_account} <-
           WhatsApp.upsert_account_from_provider(
             account.tenant_id,
             Map.merge(account_data, %{provider: account.provider})
           ),
         {:ok, final_account} <- apply_account_status(updated_account, account_data) do
      {:ok, final_account}
    end
  end

  defp apply_account_status(account, account_data) do
    case Map.get(account_data, :status) || Map.get(account_data, "status") do
      status when status in ["disconnected", "failed"] ->
        WhatsApp.mark_account_disconnected(account, account_data)

      _ ->
        WhatsApp.mark_account_connected(account, account_data)
    end
  end

  defp fetch(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
end
