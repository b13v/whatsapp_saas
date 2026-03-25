defmodule WhatsappSaas.WhatsApp.Provider do
  @moduledoc """
  Behaviour implemented by WhatsApp provider adapters.

  Provider modules isolate transport details and payload parsing, returning only
  normalized internal maps that the domain contexts can safely consume.

  Expected normalized shapes:

  * onboarding session:
    `%{external_setup_id:, setup_link:, state:, expires_at:, redirect_url:, metadata:}`
  * account:
    `%{provider:, external_account_id:, external_waba_id:, external_phone_number_id:, display_name:, phone_number:, quality_rating:, status:, onboarding_mode:, connected_at:, metadata:}`
  * template:
    `%{provider_template_id:, name:, language:, category:, status:, components:, last_synced_at:}`
  * outbound send result:
    `%{provider_message_id:, status:, sent_at:, payload:}`
  * parsed webhook events:
    `[%{provider:, topic:, provider_event_id:, tenant_hint:, account_hint:, occurred_at:, payload:, normalized_data:}]`
  """

  @type attrs :: map()
  @type normalized_result :: map()
  @type normalized_event :: map()

  @callback create_onboarding_session(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback get_onboarding_session(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback send_text_message(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback send_template_message(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback list_templates(attrs()) :: {:ok, [normalized_result()]} | {:error, term()}
  @callback fetch_account(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback parse_webhook(attrs()) :: {:ok, [normalized_event()]} | {:error, term()}
end
