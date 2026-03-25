defmodule WhatsappSaas.Workers.ProcessWebhookEventWorker do
  @moduledoc """
  Async processor for persisted webhook events.
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 10,
    unique: [period: 60, fields: [:args]]

  alias WhatsappSaas.Repo
  alias WhatsappSaas.Webhooks
  alias WhatsappSaas.Webhooks.Dispatcher
  alias WhatsappSaas.WhatsApp.WebhookEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"webhook_event_id" => webhook_event_id}}) do
    case Repo.get(WebhookEvent, webhook_event_id) do
      nil ->
        {:cancel, :webhook_event_not_found}

      %WebhookEvent{processing_status: "processed"} ->
        :ok

      %WebhookEvent{} = webhook_event ->
        case Dispatcher.process_webhook_event(webhook_event) do
          {:ok, _result} ->
            case Webhooks.mark_processed(webhook_event) do
              {:ok, _event} -> :ok
              {:error, reason} -> {:error, {:mark_processed_failed, reason}}
            end

          {:error, reason} ->
            _ = Webhooks.mark_failed(webhook_event, reason)
            {:error, reason}
        end
    end
  end
end
