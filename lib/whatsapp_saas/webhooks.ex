defmodule WhatsappSaas.Webhooks do
  @moduledoc """
  Webhook ingestion boundary. Persists raw provider payloads and enqueues async
  processing without performing domain-heavy work in the request path.
  """

  alias WhatsappSaas.Repo
  alias WhatsappSaas.Webhooks.SignatureVerifier
  alias WhatsappSaas.WhatsApp.WebhookEvent
  alias WhatsappSaas.Workers.ProcessWebhookEventWorker

  @spec ingest_webhook(String.t(), map(), map()) ::
          {:ok, WebhookEvent.t()} | {:error, term()}
  def ingest_webhook(provider, raw_payload, request_metadata) do
    with :ok <- validate_provider(provider),
         {:ok, _verification_result} <-
           normalize_signature_result(
             SignatureVerifier.verify(provider, raw_payload, request_metadata)
           ),
         {:ok, webhook_event} <- persist_webhook_event(provider, raw_payload, request_metadata),
         {:ok, _job} <- maybe_enqueue(webhook_event) do
      {:ok, webhook_event}
    end
  end

  def mark_processed(%WebhookEvent{} = webhook_event) do
    webhook_event
    |> WebhookEvent.changeset(%{
      processing_status: "processed",
      processed_at: DateTime.utc_now(),
      error_message: nil
    })
    |> Repo.update()
  end

  def mark_failed(%WebhookEvent{} = webhook_event, reason) do
    webhook_event
    |> WebhookEvent.changeset(%{
      processing_status: "failed",
      error_message: truncate_error(reason)
    })
    |> Repo.update()
  end

  defp persist_webhook_event(provider, raw_payload, request_metadata) do
    attrs = %{
      provider: provider,
      provider_event_id: infer_provider_event_id(raw_payload),
      topic: infer_topic(raw_payload),
      processing_status: "pending",
      payload: %{
        "raw_payload" => Map.new(raw_payload),
        "request_metadata" => Map.new(request_metadata)
      }
    }

    case %WebhookEvent{} |> WebhookEvent.changeset(attrs) |> Repo.insert() do
      {:ok, webhook_event} ->
        {:ok, webhook_event}

      {:error, changeset} ->
        if duplicate_provider_event_id_error?(changeset) do
          Repo.get_by(WebhookEvent,
            provider: provider,
            provider_event_id: attrs.provider_event_id
          )
          |> case do
            %WebhookEvent{} = webhook_event -> {:ok, webhook_event}
            nil -> {:error, :duplicate_webhook_event_lookup_failed}
          end
        else
          {:error, changeset}
        end
    end
  end

  defp maybe_enqueue(%WebhookEvent{processing_status: "processed"} = webhook_event),
    do: {:ok, %{skipped: true, webhook_event_id: webhook_event.id}}

  defp maybe_enqueue(%WebhookEvent{} = webhook_event) do
    %{webhook_event_id: webhook_event.id}
    |> ProcessWebhookEventWorker.new()
    |> Oban.insert()
  end

  defp infer_provider_event_id(raw_payload) do
    Map.get(raw_payload, :event_id) ||
      Map.get(raw_payload, "event_id") ||
      Map.get(raw_payload, :id) ||
      Map.get(raw_payload, "id") ||
      get_in(raw_payload, [:events, Access.at(0), "event_id"]) ||
      get_in(raw_payload, ["events", Access.at(0), "event_id"])
  end

  defp infer_topic(raw_payload) do
    Map.get(raw_payload, :topic) ||
      Map.get(raw_payload, "topic") ||
      Map.get(raw_payload, :type) ||
      Map.get(raw_payload, "type")
  end

  defp validate_provider(provider) do
    case WhatsappSaas.WhatsApp.provider_module(provider) do
      {:ok, _module} -> :ok
      {:error, :unknown_provider} -> {:error, :unknown_provider}
    end
  end

  defp normalize_signature_result(:ok), do: {:ok, :verified}
  defp normalize_signature_result({:error, _reason} = error), do: error

  defp truncate_error(reason) do
    reason
    |> inspect()
    |> String.slice(0, 500)
  end

  defp duplicate_provider_event_id_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:provider_event_id, _details} -> true
      _ -> false
    end)
  end
end
