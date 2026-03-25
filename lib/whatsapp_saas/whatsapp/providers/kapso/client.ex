defmodule WhatsappSaas.WhatsApp.Providers.Kapso.Client do
  @moduledoc """
  Low-level Kapso transport boundary.

  This module centralizes config lookup, endpoint construction, auth headers,
  and deterministic placeholder request/response contracts until a real HTTP
  client is introduced.
  """

  alias WhatsappSaas.WhatsApp.ProviderError

  @default_timeout_ms 15_000

  @spec create_onboarding_session(map()) :: {:ok, map()} | {:error, term()}
  def create_onboarding_session(attrs) do
    with {:ok, config} <- config() do
      external_setup_id = Map.get(attrs, :external_setup_id, Ecto.UUID.generate())

      {:ok,
       %{
         request: %{
           method: :post,
           url: endpoint(config, "/onboarding/sessions"),
           headers: auth_headers(config),
           body: serialize_payload(attrs)
         },
         response: %{
           id: external_setup_id,
           setup_link: "#{config.base_url}/setup/#{external_setup_id}",
           status: "created",
           expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
           redirect_url: Map.get(attrs, :redirect_url) || Map.get(attrs, "redirect_url")
         },
         metadata: %{stub: true, timeout_ms: config.timeout_ms}
       }}
    end
  end

  @spec get_onboarding_session(map()) :: {:ok, map()} | {:error, term()}
  def get_onboarding_session(attrs) do
    with {:ok, config} <- config() do
      external_setup_id =
        Map.get(attrs, :external_setup_id) || Map.get(attrs, "external_setup_id")

      {:ok,
       %{
         request: %{
           method: :get,
           url: endpoint(config, "/onboarding/sessions/#{external_setup_id}"),
           headers: auth_headers(config)
         },
         response: %{
           id: external_setup_id,
           status: Map.get(attrs, :state) || Map.get(attrs, "state") || "callback_received",
           redirect_url: Map.get(attrs, :redirect_url) || Map.get(attrs, "redirect_url")
         },
         metadata: %{stub: true}
       }}
    end
  end

  @spec send_text_message(map()) :: {:ok, map()} | {:error, term()}
  def send_text_message(attrs) do
    with {:ok, config} <- config() do
      {:ok,
       %{
         request: %{
           method: :post,
           url: endpoint(config, "/messages/text"),
           headers: auth_headers(config),
           body: serialize_payload(attrs)
         },
         response: %{
           id: Ecto.UUID.generate(),
           status: "sent",
           sent_at: DateTime.utc_now(),
           payload: %{body: Map.get(attrs, :body) || Map.get(attrs, "body")}
         },
         metadata: %{stub: true}
       }}
    end
  end

  @spec send_template_message(map()) :: {:ok, map()} | {:error, term()}
  def send_template_message(attrs) do
    with {:ok, config} <- config() do
      template = Map.get(attrs, :template) || Map.get(attrs, "template") || %{}

      {:ok,
       %{
         request: %{
           method: :post,
           url: endpoint(config, "/messages/template"),
           headers: auth_headers(config),
           body: serialize_payload(attrs)
         },
         response: %{
           id: Ecto.UUID.generate(),
           status: "sent",
           sent_at: DateTime.utc_now(),
           payload: %{template_name: Map.get(template, :name) || Map.get(template, "name")}
         },
         metadata: %{stub: true}
       }}
    end
  end

  @spec list_templates(map()) :: {:ok, map()} | {:error, term()}
  def list_templates(attrs) do
    with {:ok, config} <- config() do
      account = Map.get(attrs, :account) || Map.get(attrs, "account") || %{}

      account_id =
        Map.get(account, :external_account_id) || Map.get(account, "external_account_id")

      {:ok,
       %{
         request: %{
           method: :get,
           url: endpoint(config, "/templates"),
           headers: auth_headers(config),
           query: %{account_id: account_id}
         },
         response: [],
         metadata: %{stub: true}
       }}
    end
  end

  @spec fetch_account(map()) :: {:ok, map()} | {:error, term()}
  def fetch_account(attrs) do
    with {:ok, config} <- config() do
      external_account_id =
        Map.get(attrs, :external_account_id) || Map.get(attrs, "external_account_id")

      {:ok,
       %{
         request: %{
           method: :get,
           url: endpoint(config, "/accounts/#{external_account_id}"),
           headers: auth_headers(config)
         },
         response: %{
           id: external_account_id,
           waba_id: Map.get(attrs, :external_waba_id) || Map.get(attrs, "external_waba_id"),
           phone_number_id:
             Map.get(attrs, :external_phone_number_id) ||
               Map.get(attrs, "external_phone_number_id"),
           display_name:
             Map.get(attrs, :display_name) || Map.get(attrs, "display_name") || "Kapso Sandbox",
           phone_number: Map.get(attrs, :phone_number) || Map.get(attrs, "phone_number"),
           quality_rating: Map.get(attrs, :quality_rating) || Map.get(attrs, "quality_rating"),
           status: Map.get(attrs, :status) || Map.get(attrs, "status") || "connected",
           onboarding_mode: Map.get(attrs, :onboarding_mode) || Map.get(attrs, "onboarding_mode"),
           connected_at: Map.get(attrs, :connected_at) || Map.get(attrs, "connected_at")
         },
         metadata: %{stub: true}
       }}
    end
  end

  @spec config() ::
          {:ok, %{base_url: String.t(), api_key: String.t(), timeout_ms: pos_integer()}}
          | {:error, term()}
  def config do
    config = Application.get_env(:whatsapp_saas, __MODULE__, [])

    with {:ok, base_url} <- fetch_config(config, :kapso_base_url),
         {:ok, api_key} <- fetch_config(config, :kapso_api_key) do
      {:ok,
       %{
         base_url: String.trim_trailing(base_url, "/"),
         api_key: api_key,
         timeout_ms: Keyword.get(config, :kapso_timeout_ms, @default_timeout_ms)
       }}
    end
  end

  @spec endpoint(map(), String.t()) :: String.t()
  def endpoint(config, path), do: config.base_url <> path

  @spec auth_headers(map()) :: [{String.t(), String.t()}]
  def auth_headers(config),
    do: [{"authorization", "Bearer #{config.api_key}"}, {"content-type", "application/json"}]

  @spec serialize_payload(map()) :: map()
  def serialize_payload(attrs), do: Map.new(attrs)

  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      nil -> ProviderError.config_missing(key)
      "" -> ProviderError.config_missing(key)
      value -> {:ok, value}
    end
  end
end
