defmodule WhatsappSaas.Webhooks.SignatureVerifier do
  @moduledoc """
  Provider webhook signature verification hook.

  If no provider secret is configured, verification is skipped. Kapso's exact
  production signature contract may still need tuning, but this provides a
  real HMAC-based verification hook instead of pretending webhook verification
  exists.
  """

  @spec verify(String.t(), map(), map()) :: :ok | :skipped | {:error, :invalid_signature}
  def verify(provider, payload, request_metadata) do
    config = Application.get_env(:whatsapp_saas, __MODULE__, [])

    case Keyword.get(config, secret_key(provider)) do
      nil ->
        :skipped

      "" ->
        :skipped

      secret ->
        verify_hmac(secret, payload, request_metadata)
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

  defp secret_key(provider), do: String.to_atom("#{provider}_signature_secret")
end
