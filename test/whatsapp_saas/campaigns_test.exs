defmodule WhatsappSaas.CampaignsTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Campaigns

  describe "create_campaign/2" do
    test "owner can create a campaign" do
      %{tenant: tenant, user: owner, whatsapp_account: account} = tenant_with_user()
      template = insert(:template, tenant: tenant, whatsapp_account: account)

      attrs = %{
        tenant_id: tenant.id,
        whatsapp_account_id: account.id,
        template_id: template.id,
        created_by_user_id: owner.id,
        name: "Summer Sale"
      }

      assert {:ok, campaign} = Campaigns.create_campaign(owner, attrs)
      assert campaign.name == "Summer Sale"
      assert campaign.status == "draft"
      assert campaign.tenant_id == tenant.id
    end

    test "agent cannot create a campaign" do
      %{tenant: tenant, user: agent, whatsapp_account: account} = tenant_with_user(role: "agent")
      template = insert(:template, tenant: tenant, whatsapp_account: account)

      attrs = %{
        tenant_id: tenant.id,
        whatsapp_account_id: account.id,
        template_id: template.id,
        created_by_user_id: agent.id,
        name: "Not allowed"
      }

      assert {:error, :forbidden} = Campaigns.create_campaign(agent, attrs)
    end

    test "rejects template from different tenant" do
      %{tenant: tenant, user: owner, whatsapp_account: account} = tenant_with_user()
      %{whatsapp_account: other_account} = tenant_with_user()
      other_template = insert(:template, whatsapp_account: other_account)

      attrs = %{
        tenant_id: tenant.id,
        whatsapp_account_id: account.id,
        template_id: other_template.id,
        created_by_user_id: owner.id,
        name: "Cross-tenant"
      }

      assert {:error, :template_tenant_mismatch} = Campaigns.create_campaign(owner, attrs)
    end
  end

  describe "schedule_campaign/3" do
    setup do
      %{tenant: tenant, user: owner, whatsapp_account: account} = tenant_with_user()
      template = insert(:template, tenant: tenant, whatsapp_account: account)

      {:ok, campaign} =
        Campaigns.create_campaign(owner, %{
          tenant_id: tenant.id,
          whatsapp_account_id: account.id,
          template_id: template.id,
          created_by_user_id: owner.id,
          name: "Test Campaign"
        })

      %{owner: owner, campaign: campaign}
    end

    test "owner can schedule a campaign", %{owner: owner, campaign: campaign} do
      scheduled_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      assert {:ok, updated} = Campaigns.schedule_campaign(owner, campaign, scheduled_at)
      assert updated.status == "scheduled"
      assert updated.scheduled_at
    end

    test "agent cannot schedule", %{campaign: campaign} do
      %{user: agent} = tenant_with_user(role: "agent")

      scheduled_at = DateTime.add(DateTime.utc_now(), 3600, :second)

      # Agent from different tenant gets :unauthorized
      assert {:error, :unauthorized} = Campaigns.schedule_campaign(agent, campaign, scheduled_at)
    end
  end

  describe "cancel_campaign/2" do
    setup do
      %{tenant: tenant, user: owner, whatsapp_account: account} = tenant_with_user()
      template = insert(:template, tenant: tenant, whatsapp_account: account)

      {:ok, campaign} =
        Campaigns.create_campaign(owner, %{
          tenant_id: tenant.id,
          whatsapp_account_id: account.id,
          template_id: template.id,
          created_by_user_id: owner.id,
          name: "Cancel Me"
        })

      %{owner: owner, campaign: campaign}
    end

    test "owner can cancel a draft campaign", %{owner: owner, campaign: campaign} do
      assert {:ok, cancelled} = Campaigns.cancel_campaign(owner, campaign)
      assert cancelled.status == "cancelled"
    end
  end

  describe "build_campaign_audience/2" do
    test "returns contacts based on audience filter mode" do
      %{tenant: tenant, user: owner, whatsapp_account: account} = tenant_with_user()
      template = insert(:template, tenant: tenant, whatsapp_account: account)

      _sub = insert(:contact, tenant: tenant, opt_in_status: "subscribed")
      _unsub = insert(:contact, tenant: tenant, opt_in_status: "unknown")

      {:ok, campaign} =
        Campaigns.create_campaign(owner, %{
          tenant_id: tenant.id,
          whatsapp_account_id: account.id,
          template_id: template.id,
          created_by_user_id: owner.id,
          name: "Audience Test",
          audience_filter: %{mode: "subscribed"}
        })

      assert {:ok, contacts} = Campaigns.build_campaign_audience(owner, campaign)
      assert length(contacts) == 1
    end
  end
end
