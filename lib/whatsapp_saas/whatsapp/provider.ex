defmodule WhatsappSaas.WhatsApp.Provider do
  @moduledoc """
  Behaviour implemented by WhatsApp provider adapters.
  """

  @type attrs :: map()
  @type normalized_result :: map()

  @callback create_onboarding_session(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback get_onboarding_session(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback send_text_message(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback send_template_message(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback list_templates(attrs()) :: {:ok, [normalized_result()]} | {:error, term()}
  @callback fetch_account(attrs()) :: {:ok, normalized_result()} | {:error, term()}
  @callback parse_webhook(attrs()) :: {:ok, normalized_result()} | {:error, term()}
end
