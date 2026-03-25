defmodule WhatsappSaas.WebhooksTest do
  use WhatsappSaas.DataCase, async: true
  use Oban.Testing, repo: WhatsappSaas.Repo

  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Repo
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.{WebhookEvent, WhatsappAccount}

  test "ingest_webhook/3 persists a pending raw event and enqueues processing" do
    payload = %{
      "topic" => "message_status",
      "event_id" => "evt_ingest_1",
      "message_id" => "wamid.ingest.1",
      "status" => "delivered"
    }

    request_metadata = %{
      headers: %{"x-request-id" => "req-123"},
      ip: "127.0.0.1",
      signature: nil
    }

    assert {:ok, %WebhookEvent{} = webhook_event} =
             WhatsappSaas.Webhooks.ingest_webhook("kapso", payload, request_metadata)

    assert webhook_event.provider == "kapso"
    assert webhook_event.provider_event_id == "evt_ingest_1"
    assert webhook_event.topic == "message_status"
    assert webhook_event.processing_status == "pending"
    assert get_in(webhook_event.payload, ["request_metadata", :ip]) == "127.0.0.1"

    assert [%Oban.Job{worker: "WhatsappSaas.Workers.ProcessWebhookEventWorker"}] =
             all_enqueued(worker: WhatsappSaas.Workers.ProcessWebhookEventWorker)
  end

  test "processing inbound message webhooks is idempotent by provider_message_id" do
    tenant = tenant_fixture()
    account = whatsapp_account_fixture(tenant)

    webhook_event =
      webhook_event_fixture(%{
        provider: "kapso",
        provider_event_id: "evt-inbound-1",
        payload: %{
          "topic" => "inbound_message",
          "event_id" => "evt-inbound-1",
          "account_id" => account.external_account_id,
          "phone_number_id" => account.external_phone_number_id,
          "external_wa_id" => "wa_123",
          "phone_e164" => "+15550001111",
          "contact_name" => "Jane Doe",
          "message_id" => "wamid.001",
          "body" => "Hello from webhook",
          "timestamp" => DateTime.utc_now()
        }
      })

    assert :ok =
             WhatsappSaas.Workers.ProcessWebhookEventWorker.perform(%Oban.Job{
               args: %{"webhook_event_id" => webhook_event.id}
             })

    assert :ok =
             WhatsappSaas.Workers.ProcessWebhookEventWorker.perform(%Oban.Job{
               args: %{"webhook_event_id" => webhook_event.id}
             })

    assert Repo.aggregate(Message, :count, :id) == 1

    message = Repo.one!(Message)
    conversation = Repo.one!(Conversation)
    contact = Repo.one!(Contact)
    processed_event = Repo.get!(WebhookEvent, webhook_event.id)

    assert message.provider_message_id == "wamid.001"
    assert conversation.unread_count == 1
    assert contact.phone_e164 == "+15550001111"
    assert processed_event.processing_status == "processed"
    assert processed_event.processed_at
  end

  test "processing message status webhooks updates message state monotonically" do
    tenant = tenant_fixture()
    account = whatsapp_account_fixture(tenant)
    contact = contact_fixture(tenant)
    conversation = conversation_fixture(tenant, account, contact)

    message =
      outgoing_message_fixture(tenant, account, contact, conversation, %{
        provider_message_id: "wamid.status.1",
        status: "sent"
      })

    read_event =
      webhook_event_fixture(%{
        provider: "kapso",
        provider_event_id: "evt-status-read-1",
        payload: %{
          "topic" => "message_status",
          "event_id" => "evt-status-read-1",
          "message_id" => message.provider_message_id,
          "status" => "read",
          "read_at" => DateTime.utc_now()
        }
      })

    delivered_event =
      webhook_event_fixture(%{
        provider: "kapso",
        provider_event_id: "evt-status-delivered-1",
        payload: %{
          "topic" => "message_status",
          "event_id" => "evt-status-delivered-1",
          "message_id" => message.provider_message_id,
          "status" => "delivered",
          "delivered_at" => DateTime.utc_now()
        }
      })

    assert :ok =
             WhatsappSaas.Workers.ProcessWebhookEventWorker.perform(%Oban.Job{
               args: %{"webhook_event_id" => read_event.id}
             })

    assert :ok =
             WhatsappSaas.Workers.ProcessWebhookEventWorker.perform(%Oban.Job{
               args: %{"webhook_event_id" => delivered_event.id}
             })

    updated_message = Repo.get!(Message, message.id)

    assert updated_message.status == "read"
    assert updated_message.read_at
    assert updated_message.delivered_at
  end

  defp tenant_fixture(attrs \\ %{}) do
    params =
      Map.merge(
        %{
          name: "Tenant #{System.unique_integer([:positive])}",
          slug: "tenant-#{System.unique_integer([:positive])}",
          status: "active",
          plan: "starter",
          vertical: "clinic",
          onboarding_status: "not_started"
        },
        attrs
      )

    %Tenant{} |> Tenant.changeset(params) |> Repo.insert!()
  end

  defp whatsapp_account_fixture(%Tenant{} = tenant, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          tenant_id: tenant.id,
          provider: "kapso",
          external_account_id: "acct-#{System.unique_integer([:positive])}",
          external_phone_number_id: "phone-#{System.unique_integer([:positive])}",
          status: "connected"
        },
        attrs
      )

    %WhatsappAccount{} |> WhatsappAccount.changeset(params) |> Repo.insert!()
  end

  defp contact_fixture(%Tenant{} = tenant, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          tenant_id: tenant.id,
          phone_e164: "+1555#{System.unique_integer([:positive])}",
          opt_in_status: "unknown"
        },
        attrs
      )

    %Contact{} |> Contact.changeset(params) |> Repo.insert!()
  end

  defp conversation_fixture(
         %Tenant{} = tenant,
         %WhatsappAccount{} = account,
         %Contact{} = contact
       ) do
    %Conversation{}
    |> Conversation.changeset(%{
      tenant_id: tenant.id,
      whatsapp_account_id: account.id,
      contact_id: contact.id,
      status: "open",
      unread_count: 0
    })
    |> Repo.insert!()
  end

  defp outgoing_message_fixture(
         %Tenant{} = tenant,
         %WhatsappAccount{} = account,
         %Contact{} = contact,
         %Conversation{} = conversation,
         attrs
       ) do
    params =
      Map.merge(
        %{
          tenant_id: tenant.id,
          conversation_id: conversation.id,
          whatsapp_account_id: account.id,
          contact_id: contact.id,
          direction: "outbound",
          kind: "text",
          status: "queued",
          body: "Outbound body"
        },
        attrs
      )

    %Message{} |> Message.changeset(params) |> Repo.insert!()
  end

  defp webhook_event_fixture(attrs) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(
      Map.merge(
        %{
          provider: "kapso",
          payload: %{},
          processing_status: "pending"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
