defmodule WhatsappSaas.Webhooks.SignatureVerifier do
  @moduledoc """
  Provider webhook signature verification hook.

  Each known provider maps to an atom in the module config. Unknown providers
  are rejected immediately. Verification fails closed if no secret is
  configured.
  """

  @known_providers ~w(kapso)

  @spec verify(String.t(), map(), map()) :: :ok | {:error, :invalid_signature | :unknown_provider | :secret_not_configured}
  def verify(provider, payload, request_metadata) when is_binary(provider) do
    if provider in @known_providers do
      config = Application.get_env(:whatsapp_saas, __MODULE__, [])
      key = String.to_existing_atom("#{provider}_signature_secret")

      case Keyword.get(config, key) do
        nil ->
          {:error, :secret_not_configured}

        "" ->
          {:error, :secret_not_configured}

        secret ->
          verify_hmac(secret, payload, request_metadata)
      end
    else
      {:error, :unknown_provider}
    end
  end

  defp verify_hmac(secret, payload, request_metadata) do
    signature =
      Map.get(request_metadata, :signature) ||
        Map.get(request_metadata, "signature") ||
        get_in(request_metadata, [:headers, "x-kapso-signature"]) ||
        get_in(request_metadata, ["headers", "x-kapso-signature"])

    if is_binary(signature) and
         Plug.Crypto.secure_compare(signature, expected_signature(secret, payload)) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp expected_signature(secret, payload) do
    digest =
      :crypto.mac(:hmac, :sha256, secret, Jason.encode!(payload))
      |> Base.encode16(case: :lower)

    "sha256=" <> digest
  end

end
