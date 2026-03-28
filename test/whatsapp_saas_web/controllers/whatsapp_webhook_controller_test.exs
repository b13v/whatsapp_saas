defmodule WhatsappSaasWeb.WhatsAppWebhookControllerTest do
  use WhatsappSaasWeb.ConnCase, async: true

  alias WhatsappSaas.Repo
  alias WhatsappSaas.WhatsApp.WebhookEvent

  test "POST /webhooks/whatsapp/kapso returns quickly and persists the raw payload", %{conn: conn} do
    payload = %{
      "topic" => "message_status",
      "event_id" => "evt-controller-1",
      "message_id" => "wamid.controller.1",
      "status" => "sent"
    }

    signature = compute_signature(payload)

    conn =
      conn
      |> Plug.Conn.put_req_header("x-kapso-signature", signature)
      |> post("/webhooks/whatsapp/kapso", payload)

    assert json_response(conn, 202) == %{"ok" => true}

    event = Repo.get_by!(WebhookEvent, provider_event_id: "evt-controller-1")
    assert event.provider == "kapso"
    assert event.processing_status == "pending"
  end

  test "POST /webhooks/whatsapp/kapso rejects invalid signature", %{conn: conn} do
    payload = %{
      "topic" => "message_status",
      "event_id" => "evt-bad-sig",
      "message_id" => "wamid.bad",
      "status" => "sent"
    }

    conn =
      conn
      |> Plug.Conn.put_req_header("x-kapso-signature", "sha256=badsignature")
      |> post("/webhooks/whatsapp/kapso", payload)

    assert json_response(conn, 401) == %{"ok" => false, "error" => "invalid_signature"}
  end

  defp compute_signature(payload) do
    secret =
      Application.get_env(:whatsapp_saas, WhatsappSaas.Webhooks.SignatureVerifier, [])
      |> Keyword.get(:kapso_signature_secret)

    digest =
      :crypto.mac(:hmac, :sha256, secret, Jason.encode!(payload))
      |> Base.encode16(case: :lower)

    "sha256=" <> digest
  end
end
