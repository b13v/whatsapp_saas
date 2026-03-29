defmodule WhatsappSaas.InboxTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Inbox
  alias WhatsappSaas.Inbox.Conversation

  describe "get_or_create_open_conversation/3" do
    test "creates a new conversation when none exists" do
      tenant = insert(:tenant)
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)

      assert {:ok, %Conversation{} = conversation} =
               Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)

      assert conversation.tenant_id == tenant.id
      assert conversation.whatsapp_account_id == account.id
      assert conversation.contact_id == contact.id
      assert conversation.status == "open"
    end

    test "returns existing open conversation" do
      tenant = insert(:tenant)
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)

      {:ok, original} =
        Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)

      assert {:ok, returned} =
               Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)

      assert returned.id == original.id
    end
  end

  describe "list_conversations/3" do
    test "returns conversations scoped to tenant" do
      %{tenant: tenant, user: owner} = tenant_with_user()
      _conv = insert(:conversation, tenant: tenant)
      _other = insert(:conversation)

      result = Inbox.list_conversations(owner, tenant.id)
      assert length(result) == 1
    end

    test "rejects unauthorized user" do
      %{tenant: tenant} = tenant_with_user()
      %{user: other_user} = tenant_with_user()

      assert {:error, :unauthorized} = Inbox.list_conversations(other_user, tenant.id)
    end
  end

  describe "close_conversation/2 and reopen_conversation/2" do
    setup do
      %{tenant: tenant, user: owner} = tenant_with_user()
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)
      {:ok, conversation} = Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)
      %{owner: owner, conversation: conversation}
    end

    test "owner can close a conversation", %{owner: owner, conversation: conv} do
      assert {:ok, closed} = Inbox.close_conversation(owner, conv)
      assert closed.status == "closed"
      assert closed.closed_at
    end

    test "owner can reopen a closed conversation", %{owner: owner, conversation: conv} do
      {:ok, closed} = Inbox.close_conversation(owner, conv)
      assert {:ok, reopened} = Inbox.reopen_conversation(owner, closed)
      assert reopened.status == "open"
      assert is_nil(reopened.closed_at)
    end

    test "viewer cannot close a conversation", %{conversation: conv} do
      tenant = insert(:tenant)
      viewer = insert(:user, tenant: tenant, role: "viewer")

      # Viewer from different tenant gets :unauthorized, not :forbidden
      assert {:error, :unauthorized} = Inbox.close_conversation(viewer, conv)
    end
  end

  describe "message status lifecycle" do
    setup do
      tenant = insert(:tenant)
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)
      {:ok, conversation} = Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)
      %{conversation: conversation}
    end

    test "create_outgoing_message/2 creates a queued message", %{conversation: conv} do
      assert {:ok, message} =
               Inbox.create_outgoing_message(conv, %{
                 body: "Hello world",
                 kind: "text",
                 provider_message_id: "wamid.test.1"
               })

      assert message.direction == "outbound"
      assert message.status == "queued"
      assert message.body == "Hello world"
    end

    test "mark_message_sent/2 updates status to sent", %{conversation: conv} do
      {:ok, message} =
        Inbox.create_outgoing_message(conv, %{body: "Hi", kind: "text"})

      assert {:ok, sent} = Inbox.mark_message_sent(message)
      assert sent.status == "sent"
      assert sent.sent_at
    end

    test "mark_message_delivered/2 updates status to delivered", %{conversation: conv} do
      {:ok, message} =
        Inbox.create_outgoing_message(conv, %{body: "Hi", kind: "text"})

      {:ok, sent} = Inbox.mark_message_sent(message)
      assert {:ok, delivered} = Inbox.mark_message_delivered(sent)
      assert delivered.status == "delivered"
      assert delivered.delivered_at
    end

    test "mark_message_read/2 updates status to read", %{conversation: conv} do
      {:ok, message} =
        Inbox.create_outgoing_message(conv, %{body: "Hi", kind: "text"})

      {:ok, sent} = Inbox.mark_message_sent(message)
      {:ok, delivered} = Inbox.mark_message_delivered(sent)
      assert {:ok, read} = Inbox.mark_message_read(delivered)
      assert read.status == "read"
      assert read.read_at
    end

    test "mark_message_failed/2 updates status to failed", %{conversation: conv} do
      {:ok, message} =
        Inbox.create_outgoing_message(conv, %{body: "Hi", kind: "text"})

      assert {:ok, failed} = Inbox.mark_message_failed(message, %{error_code: "RATE_LIMITED"})
      assert failed.status == "failed"
      assert failed.error_code == "RATE_LIMITED"
    end
  end

  describe "apply_provider_message_status/3 monotonic status" do
    setup do
      tenant = insert(:tenant)
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)
      {:ok, conversation} = Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)
      %{conversation: conversation}
    end

    test "does not downgrade status from read to delivered", %{conversation: conv} do
      {:ok, msg} =
        Inbox.create_outgoing_message(conv, %{body: "Hi", kind: "text"})

      {:ok, msg} = Inbox.mark_message_sent(msg)
      {:ok, msg} = Inbox.mark_message_delivered(msg)
      {:ok, msg} = Inbox.mark_message_read(msg)

      assert {:ok, unchanged} = Inbox.apply_provider_message_status(msg, "delivered", %{})
      assert unchanged.status == "read"
    end
  end

  describe "get_message_by_provider_message_id/1" do
    test "finds message by provider ID" do
      tenant = insert(:tenant)
      account = insert(:whatsapp_account, tenant: tenant)
      contact = insert(:contact, tenant: tenant)
      {:ok, conv} = Inbox.get_or_create_open_conversation(tenant.id, account.id, contact.id)

      {:ok, msg} =
        Inbox.create_outgoing_message(conv, %{
          body: "test",
          kind: "text",
          provider_message_id: "wamid.findme"
        })

      assert {:ok, found} = Inbox.get_message_by_provider_message_id("wamid.findme")
      assert found.id == msg.id
    end

    test "returns not_found for unknown provider ID" do
      assert {:error, :not_found} = Inbox.get_message_by_provider_message_id("wamid.nonexistent")
    end
  end
end
