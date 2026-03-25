defmodule WhatsappSaas.WhatsApp.Providers.Kapso.Normalizer do
  @moduledoc """
  Kapso-specific payload normalization into stable internal maps.

  All raw field digging and timestamp coercion should stay here so domain
  contexts remain provider-agnostic.
  """

  alias WhatsappSaas.WhatsApp.ProviderError

  @provider "kapso"

  @spec normalize_onboarding_session(map()) :: {:ok, map()} | {:error, term()}
  def normalize_onboarding_session(raw) when is_map(raw) do
    response = response_map(raw)

    {:ok,
     %{
       external_setup_id: get_first(response, [:id, :external_setup_id, :setup_id]),
       setup_link: get_first(response, [:setup_link, :url]),
       state: get_first(response, [:status, :state]) || "created",
       expires_at: parse_datetime(get_first(response, [:expires_at, :expiration_time])),
       redirect_url: get_first(response, [:redirect_url]),
       metadata: metadata(raw)
     }}
  end

  def normalize_onboarding_session(other),
    do: ProviderError.normalization_failed({:invalid_onboarding_session, other})

  @spec normalize_account(map()) :: {:ok, map()} | {:error, term()}
  def normalize_account(raw) when is_map(raw) do
    response = response_map(raw)

    {:ok,
     %{
       provider: @provider,
       external_account_id: get_first(response, [:id, :external_account_id, :account_id]),
       external_waba_id: get_first(response, [:waba_id, :external_waba_id]),
       external_phone_number_id:
         get_first(response, [:phone_number_id, :external_phone_number_id]),
       display_name: get_first(response, [:display_name, :name]),
       phone_number: get_first(response, [:phone_number]),
       quality_rating: get_first(response, [:quality_rating]),
       status: get_first(response, [:status]) || "connected",
       onboarding_mode: get_first(response, [:onboarding_mode]),
       connected_at: parse_datetime(get_first(response, [:connected_at])),
       metadata: metadata(raw)
     }}
  end

  def normalize_account(other), do: ProviderError.normalization_failed({:invalid_account, other})

  @spec normalize_template(map()) :: {:ok, map()} | {:error, term()}
  def normalize_template(raw) when is_map(raw) do
    response = response_map(raw)

    {:ok,
     %{
       provider_template_id: get_first(response, [:id, :provider_template_id]),
       name: get_first(response, [:name]) || "unnamed_template",
       language: get_first(response, [:language, :locale]),
       category: get_first(response, [:category]),
       status: get_first(response, [:status]),
       components: normalize_components(get_first(response, [:components]) || %{}),
       last_synced_at: parse_datetime(get_first(response, [:last_synced_at, :updated_at])),
       metadata: metadata(raw)
     }}
  end

  def normalize_template(other),
    do: ProviderError.normalization_failed({:invalid_template, other})

  @spec normalize_templates(list() | map()) :: {:ok, [map()]} | {:error, term()}
  def normalize_templates(raw) when is_list(raw) do
    Enum.reduce_while(raw, {:ok, []}, fn entry, {:ok, acc} ->
      case normalize_template(entry) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, templates} -> {:ok, Enum.reverse(templates)}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_templates(%{response: response}) when is_list(response),
    do: normalize_templates(response)

  def normalize_templates(other),
    do: ProviderError.normalization_failed({:invalid_templates, other})

  @spec normalize_send_result(map()) :: {:ok, map()} | {:error, term()}
  def normalize_send_result(raw) when is_map(raw) do
    response = response_map(raw)

    {:ok,
     %{
       provider_message_id: get_first(response, [:id, :provider_message_id, :message_id]),
       status: get_first(response, [:status]) || "sent",
       sent_at:
         parse_datetime(get_first(response, [:sent_at, :created_at])) || DateTime.utc_now(),
       payload: Map.put(response, :raw, raw)
     }}
  end

  def normalize_send_result(other),
    do: ProviderError.normalization_failed({:invalid_send_result, other})

  @spec normalize_webhook_events(map()) :: {:ok, [map()]} | {:error, term()}
  def normalize_webhook_events(raw) when is_map(raw) do
    events =
      cond do
        is_list(raw["events"]) -> raw["events"]
        is_list(raw[:events]) -> raw[:events]
        is_list(raw["entries"]) -> raw["entries"]
        is_list(raw[:entries]) -> raw[:entries]
        true -> [raw]
      end

    normalized =
      Enum.map(events, fn event ->
        event_map = Map.new(event)
        topic = webhook_topic(event_map)

        %{
          provider: @provider,
          topic: topic,
          provider_event_id: get_first(event_map, [:id, :event_id, :provider_event_id]),
          tenant_hint: normalize_hint(get_first(event_map, [:tenant_hint])),
          account_hint:
            normalize_hint(%{
              external_account_id: get_first(event_map, [:account_id, :external_account_id]),
              external_waba_id: get_first(event_map, [:waba_id, :external_waba_id]),
              external_phone_number_id:
                get_first(event_map, [:phone_number_id, :external_phone_number_id])
            }),
          occurred_at:
            parse_datetime(get_first(event_map, [:occurred_at, :timestamp, :created_at])),
          payload: event_map,
          normalized_data: normalized_event_data(topic, event_map)
        }
      end)

    {:ok, normalized}
  end

  def normalize_webhook_events(other),
    do: ProviderError.normalization_failed({:invalid_webhook_payload, other})

  defp normalized_event_data("inbound_message", event_map) do
    %{
      external_wa_id: get_first(event_map, [:external_wa_id, :wa_id]),
      phone_e164: get_first(event_map, [:phone_e164, :phone_number, :from]),
      contact_name: get_first(event_map, [:contact_name, :name]),
      message: %{
        provider_message_id: get_first(event_map, [:message_id, :provider_message_id]),
        kind: get_first(event_map, [:message_type, :kind]) || "text",
        body: get_first(event_map, [:body, :text]),
        payload: event_map,
        sent_at: parse_datetime(get_first(event_map, [:sent_at, :timestamp]))
      }
    }
  end

  defp normalized_event_data("message_status", event_map) do
    %{
      provider_message_id: get_first(event_map, [:message_id, :provider_message_id]),
      status: get_first(event_map, [:status]) || "sent",
      sent_at: parse_datetime(get_first(event_map, [:sent_at])),
      delivered_at: parse_datetime(get_first(event_map, [:delivered_at])),
      read_at: parse_datetime(get_first(event_map, [:read_at])),
      failed_at: parse_datetime(get_first(event_map, [:failed_at])),
      error_code: get_first(event_map, [:error_code]),
      error_message: get_first(event_map, [:error_message])
    }
  end

  defp normalized_event_data("template_updated", event_map) do
    %{
      template: %{
        provider_template_id: get_first(event_map, [:template_id, :provider_template_id]),
        name: get_first(event_map, [:template_name, :name]),
        language: get_first(event_map, [:language]),
        category: get_first(event_map, [:category]),
        status: get_first(event_map, [:status]),
        components: normalize_components(get_first(event_map, [:components]) || %{})
      }
    }
  end

  defp normalized_event_data(topic, event_map)
       when topic in ["onboarding_update", "account_updated"] do
    %{
      account: %{
        provider: @provider,
        external_account_id: get_first(event_map, [:account_id, :external_account_id]),
        external_waba_id: get_first(event_map, [:waba_id, :external_waba_id]),
        external_phone_number_id:
          get_first(event_map, [:phone_number_id, :external_phone_number_id]),
        display_name: get_first(event_map, [:display_name]),
        phone_number: get_first(event_map, [:phone_number]),
        quality_rating: get_first(event_map, [:quality_rating]),
        status: get_first(event_map, [:status]) || "connected",
        onboarding_mode: get_first(event_map, [:onboarding_mode]),
        connected_at: parse_datetime(get_first(event_map, [:connected_at]))
      }
    }
  end

  defp normalized_event_data(_topic, event_map), do: %{payload: event_map}

  defp webhook_topic(event_map) do
    topic =
      get_first(event_map, [:topic, :type, :event_type, :status_topic]) ||
        infer_topic_from_shape(event_map)

    topic
    |> to_string()
    |> canonical_topic()
  end

  defp infer_topic_from_shape(event_map) do
    cond do
      Map.has_key?(event_map, "template_name") or Map.has_key?(event_map, :template_name) ->
        "template_updated"

      Map.has_key?(event_map, "message_id") or Map.has_key?(event_map, :message_id) ->
        if get_first(event_map, [:status]), do: "message_status", else: "inbound_message"

      Map.has_key?(event_map, "account_id") or Map.has_key?(event_map, :account_id) ->
        "account_updated"

      true ->
        "onboarding_update"
    end
  end

  defp canonical_topic(topic) do
    case topic do
      "message.received" -> "inbound_message"
      "message_received" -> "inbound_message"
      "message.status" -> "message_status"
      "message_status_changed" -> "message_status"
      "account.connected" -> "account_updated"
      "account.updated" -> "account_updated"
      "business_account_update" -> "onboarding_update"
      other -> other
    end
  end

  defp response_map(%{response: response}) when is_map(response), do: Map.new(response)
  defp response_map(%{"response" => response}) when is_map(response), do: Map.new(response)
  defp response_map(raw), do: Map.new(raw)

  defp metadata(raw) do
    base =
      case Map.get(raw, :metadata) || Map.get(raw, "metadata") do
        metadata when is_map(metadata) -> metadata
        _ -> %{}
      end

    Map.put(base, :raw, raw)
  end

  defp get_first(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key) || Map.get(map, to_string(key))
    end)
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: value
  defp parse_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")

  defp parse_datetime(value) when is_integer(value) do
    DateTime.from_unix!(value)
  rescue
    _ -> nil
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp normalize_components(components) when is_map(components), do: components
  defp normalize_components(components) when is_list(components), do: %{items: components}
  defp normalize_components(_), do: %{}

  defp normalize_hint(nil), do: nil

  defp normalize_hint(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 -> nil
      hint -> hint
    end
  end
end
