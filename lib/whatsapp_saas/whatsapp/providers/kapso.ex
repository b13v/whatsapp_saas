defmodule WhatsappSaas.WhatsApp.Providers.Kapso do
  @moduledoc """
  Kapso provider skeleton returning normalized placeholder contracts.

  TODO: Replace these stub responses with real HTTP integration once
  credentials, endpoints, and webhook contracts are finalized.
  """

  @behaviour WhatsappSaas.WhatsApp.Provider

  @impl true
  def create_onboarding_session(attrs) do
    external_setup_id = Map.get(attrs, :external_setup_id, Ecto.UUID.generate())

    {:ok,
     %{
       external_setup_id: external_setup_id,
       setup_link: "https://kapso.example/setup/#{external_setup_id}",
       state: "created",
       expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
       metadata: %{provider: "kapso", stub: true}
     }}
  end

  @impl true
  def get_onboarding_session(attrs) do
    {:ok,
     %{
       external_setup_id: Map.get(attrs, :external_setup_id),
       state: Map.get(attrs, :state, "callback_received"),
       metadata: %{provider: "kapso", stub: true}
     }}
  end

  @impl true
  def send_text_message(attrs) do
    {:ok,
     %{
       provider_message_id: Ecto.UUID.generate(),
       status: "sent",
       sent_at: DateTime.utc_now(),
       payload: Map.put(Map.get(attrs, :payload, %{}), :stub, true)
     }}
  end

  @impl true
  def send_template_message(attrs) do
    {:ok,
     %{
       provider_message_id: Ecto.UUID.generate(),
       status: "sent",
       sent_at: DateTime.utc_now(),
       payload: Map.put(Map.get(attrs, :payload, %{}), :stub, true)
     }}
  end

  @impl true
  def list_templates(_attrs), do: {:ok, []}

  @impl true
  def fetch_account(attrs) do
    {:ok,
     %{
       provider: "kapso",
       external_account_id: Map.get(attrs, :external_account_id),
       external_waba_id: Map.get(attrs, :external_waba_id),
       external_phone_number_id: Map.get(attrs, :external_phone_number_id),
       display_name: Map.get(attrs, :display_name, "Kapso Sandbox"),
       phone_number: Map.get(attrs, :phone_number),
       quality_rating: Map.get(attrs, :quality_rating),
       status: Map.get(attrs, :status, "connected"),
       onboarding_mode: Map.get(attrs, :onboarding_mode),
       connected_at: Map.get(attrs, :connected_at, DateTime.utc_now()),
       metadata: %{provider: "kapso", stub: true}
     }}
  end

  @impl true
  def parse_webhook(payload), do: {:ok, %{provider: "kapso", payload: payload, stub: true}}
end
