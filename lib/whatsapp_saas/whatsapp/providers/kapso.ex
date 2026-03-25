defmodule WhatsappSaas.WhatsApp.Providers.Kapso do
  @moduledoc """
  Kapso provider adapter.

  This module keeps public provider operations small by delegating transport
  concerns to `Kapso.Client` and all payload shaping to `Kapso.Normalizer`.

  TODO: replace placeholder endpoints and deterministic stub responses with
  real HTTP integration once Kapso credentials and final API docs are confirmed.
  """

  @behaviour WhatsappSaas.WhatsApp.Provider

  alias WhatsappSaas.WhatsApp.Providers.Kapso.{Client, Normalizer}

  @impl true
  def create_onboarding_session(attrs) do
    with {:ok, raw} <- Client.create_onboarding_session(attrs),
         {:ok, normalized} <- Normalizer.normalize_onboarding_session(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def get_onboarding_session(attrs) do
    with {:ok, raw} <- Client.get_onboarding_session(attrs),
         {:ok, normalized} <- Normalizer.normalize_onboarding_session(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def send_text_message(attrs) do
    with {:ok, raw} <- Client.send_text_message(attrs),
         {:ok, normalized} <- Normalizer.normalize_send_result(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def send_template_message(attrs) do
    with {:ok, raw} <- Client.send_template_message(attrs),
         {:ok, normalized} <- Normalizer.normalize_send_result(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def list_templates(attrs) do
    with {:ok, raw} <- Client.list_templates(attrs),
         {:ok, normalized} <- Normalizer.normalize_templates(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def fetch_account(attrs) do
    with {:ok, raw} <- Client.fetch_account(attrs),
         {:ok, normalized} <- Normalizer.normalize_account(raw) do
      {:ok, normalized}
    end
  end

  @impl true
  def parse_webhook(payload), do: Normalizer.normalize_webhook_events(payload)
end
