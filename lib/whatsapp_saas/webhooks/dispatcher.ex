defmodule WhatsappSaas.Webhooks.Dispatcher do
  @moduledoc """
  Parses raw webhook payloads through the provider boundary and routes the
  resulting normalized events for domain processing.
  """

  alias WhatsappSaas.Webhooks.Processor
  alias WhatsappSaas.WhatsApp.WebhookEvent

  @spec process_webhook_event(WebhookEvent.t()) :: {:ok, map()} | {:error, term()}
  def process_webhook_event(%WebhookEvent{} = webhook_event) do
    with {:ok, provider} <- WhatsappSaas.WhatsApp.provider_module(webhook_event.provider),
         {:ok, events} <- parse(provider, raw_payload(webhook_event)),
         {:ok, results} <- process_events(webhook_event, events) do
      {:ok, %{count: length(results), results: results}}
    end
  end

  defp parse(provider, raw_payload) do
    case provider.parse_webhook(raw_payload) do
      {:ok, events} -> {:ok, events}
      {:error, reason} -> {:error, {:provider_parse_failed, reason}}
    end
  end

  defp process_events(webhook_event, events) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case Processor.process_normalized_event(webhook_event, event) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, {:domain_processing_failed, reason}}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp raw_payload(%WebhookEvent{payload: payload}) do
    Map.get(payload, "raw_payload") || Map.get(payload, :raw_payload) || payload || %{}
  end
end
