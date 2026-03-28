defmodule WhatsappSaas.ContactsTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Contacts

  describe "create_contact/2" do
    test "owner can create a contact in their tenant" do
      %{tenant: tenant, user: owner} = tenant_with_user()

      assert {:ok, contact} =
               Contacts.create_contact(owner, %{
                 tenant_id: tenant.id,
                 phone_e164: "+15550001001",
                 name: "Alice"
               })

      assert contact.phone_e164 == "+15550001001"
      assert contact.tenant_id == tenant.id
    end

    test "rejects creation from user in different tenant" do
      %{tenant: tenant} = tenant_with_user()
      %{user: other_user} = tenant_with_user()

      assert {:error, :unauthorized} =
               Contacts.create_contact(other_user, %{
                 tenant_id: tenant.id,
                 phone_e164: "+15550001002"
               })
    end
  end

  describe "upsert_contact_from_inbound/2" do
    test "creates contact when not found" do
      tenant = insert(:tenant)

      assert {:ok, contact} =
               Contacts.upsert_contact_from_inbound(tenant.id, %{
                 phone_e164: "+15550001003",
                 contact_name: "Bob",
                 external_wa_id: "wa_bob_123"
               })

      assert contact.phone_e164 == "+15550001003"
      assert contact.name == "Bob"
      assert contact.external_wa_id == "wa_bob_123"
    end

    test "updates last_seen_at on existing contact without overwriting name" do
      tenant = insert(:tenant)
      existing = insert(:contact, tenant: tenant, name: "Charlie", phone_e164: "+15550001004")

      assert {:ok, updated} =
               Contacts.upsert_contact_from_inbound(tenant.id, %{
                 phone_e164: "+15550001004",
                 contact_name: "Charles",
                 external_wa_id: "wa_charles"
               })

      assert updated.id == existing.id
      assert updated.name == "Charlie"
      assert updated.last_seen_at
    end
  end

  describe "list_contacts_for_audience/2" do
    test "returns all contacts for tenant in default mode" do
      tenant = insert(:tenant)
      _c1 = insert(:contact, tenant: tenant)
      _c2 = insert(:contact, tenant: tenant)
      _other = insert(:contact)

      assert {:ok, contacts} = Contacts.list_contacts_for_audience(tenant.id, "all_contacts")
      assert length(contacts) == 2
    end

    test "filters by subscribed opt_in_status" do
      tenant = insert(:tenant)
      _sub = insert(:contact, tenant: tenant, opt_in_status: "subscribed")
      _unsub = insert(:contact, tenant: tenant, opt_in_status: "unsubscribed")

      assert {:ok, contacts} = Contacts.list_contacts_for_audience(tenant.id, "subscribed")
      assert length(contacts) == 1
    end

    test "filters by tagged_returning" do
      tenant = insert(:tenant)
      _tagged = insert(:contact, tenant: tenant, tags: %{"returning" => "true"})
      _untagged = insert(:contact, tenant: tenant, tags: %{})

      assert {:ok, contacts} = Contacts.list_contacts_for_audience(tenant.id, "tagged_returning")
      assert length(contacts) == 1
    end
  end

  describe "update_opt_in_status/3" do
    test "subscribes contact and creates consent record" do
      tenant = insert(:tenant)
      contact = insert(:contact, tenant: tenant, opt_in_status: "unknown")

      assert {:ok, updated} =
               Contacts.update_opt_in_status(contact, "subscribed", %{
                 source: "manual",
                 proof: %{"admin_id" => "test"}
               })

      assert updated.opt_in_status == "subscribed"
      assert updated.opted_in_at
    end

    test "unsubscribes contact" do
      tenant = insert(:tenant)
      contact = insert(:contact, tenant: tenant, opt_in_status: "subscribed", opted_in_at: DateTime.utc_now())

      assert {:ok, updated} = Contacts.update_opt_in_status(contact, "unsubscribed")
      assert updated.opt_in_status == "unsubscribed"
      assert updated.unsubscribed_at
    end
  end
end
