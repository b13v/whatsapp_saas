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

    conn = post(conn, "/webhooks/whatsapp/kapso", payload)

    assert json_response(conn, 202) == %{"ok" => true}

    event = Repo.get_by!(WebhookEvent, provider_event_id: "evt-controller-1")
    assert event.provider == "kapso"
    assert event.processing_status == "pending"
  end
end
