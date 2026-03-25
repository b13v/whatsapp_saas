defmodule WhatsappSaasWeb.WhatsAppWebhookController do
  @moduledoc """
  Thin provider webhook receipt endpoint.
  """

  use WhatsappSaasWeb, :controller

  alias WhatsappSaas.Webhooks

  def kapso(conn, params) do
    request_metadata = %{
      headers: Map.new(conn.req_headers),
      ip: format_ip(conn.remote_ip),
      request_id: List.first(Plug.Conn.get_resp_header(conn, "x-request-id")),
      signature: List.first(get_req_header(conn, "x-kapso-signature"))
    }

    case Webhooks.ingest_webhook("kapso", params, request_metadata) do
      {:ok, _event} ->
        conn
        |> put_status(:accepted)
        |> json(%{ok: true})

      {:error, :invalid_signature} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{ok: false, error: "invalid_signature"})

      {:error, _reason} ->
        conn
        |> put_status(:accepted)
        |> json(%{ok: false})
    end
  end

  defp format_ip(nil), do: nil
  defp format_ip(tuple), do: :inet.ntoa(tuple) |> to_string()
end
