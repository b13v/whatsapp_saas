defmodule WhatsappSaas.Factory do
  use ExMachina.Ecto, repo: WhatsappSaas.Repo

  alias WhatsappSaas.Accounts.User
  alias WhatsappSaas.Contacts.Contact
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Tenants.Tenant
  alias WhatsappSaas.WhatsApp.{Template, WebhookEvent, WhatsappAccount}

  def tenant_factory do
    %Tenant{
      name: sequence(:name, &"Tenant #{&1}"),
      slug: sequence(:slug, &"tenant-#{&1}"),
      status: "active",
      plan: "starter",
      vertical: "clinic",
      onboarding_status: "not_started"
    }
  end

  def user_factory do
    %User{
      tenant: build(:tenant),
      email: sequence(:email, &"user-#{&1}@example.com"),
      hashed_password: :crypto.strong_rand_bytes(32) |> Base.encode64(),
      role: "owner",
      status: "active"
    }
  end

  def whatsapp_account_factory do
    %WhatsappAccount{
      tenant: build(:tenant),
      provider: "kapso",
      external_account_id: sequence(:ext_acct, &"acct-#{&1}"),
      external_phone_number_id: sequence(:ext_phone, &"phone-#{&1}"),
      status: "connected"
    }
  end

  def contact_factory do
    %Contact{
      tenant: build(:tenant),
      phone_e164: sequence(:phone, &"+1555#{String.pad_leading(Integer.to_string(&1), 8, "0")}"),
      opt_in_status: "unknown"
    }
  end

  def conversation_factory do
    %Conversation{
      tenant: build(:tenant),
      whatsapp_account: build(:whatsapp_account),
      contact: build(:contact),
      status: "open",
      unread_count: 0
    }
  end

  def message_factory do
    %Message{
      tenant: build(:tenant),
      conversation: build(:conversation),
      whatsapp_account: build(:whatsapp_account),
      contact: build(:contact),
      direction: "inbound",
      kind: "text",
      status: "queued",
      body: "Hello"
    }
  end

  def webhook_event_factory do
    %WebhookEvent{
      provider: "kapso",
      provider_event_id: sequence(:event_id, &"evt-#{&1}"),
      topic: "inbound_message",
      payload: %{},
      processing_status: "pending"
    }
  end

  def template_factory do
    %Template{
      tenant: build(:tenant),
      whatsapp_account: build(:whatsapp_account),
      name: sequence(:template_name, &"template_#{&1}"),
      language: "en",
      category: "marketing",
      status: "approved"
    }
  end

  @doc "Inserts a tenant, user, and whatsapp_account for a complete tenant setup."
  def tenant_with_user(attrs \\ %{}) do
    attrs = Map.new(attrs)
    tenant = insert(:tenant, Map.take(attrs, [:plan, :vertical]))
    user = insert(:user, tenant: tenant, role: Map.get(attrs, :role, "owner"))
    account = insert(:whatsapp_account, tenant: tenant)
    %{tenant: tenant, user: user, whatsapp_account: account}
  end
end
