defmodule WhatsappSaas.Accounts.PolicyTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Accounts.Policy

  describe "authorize_tenant_access/2" do
    test "allows user belonging to the tenant" do
      user = insert(:user)
      assert :ok = Policy.authorize_tenant_access(user, user.tenant_id)
    end

    test "rejects user from a different tenant" do
      user = insert(:user)
      other_tenant = insert(:tenant)
      assert {:error, :unauthorized} = Policy.authorize_tenant_access(user, other_tenant.id)
    end

    test "rejects nil user" do
      tenant = insert(:tenant)
      assert {:error, :unauthorized} = Policy.authorize_tenant_access(nil, tenant.id)
    end

    test "rejects disabled user" do
      user = insert(:user, status: "disabled")
      assert {:error, :forbidden} = Policy.authorize_tenant_access(user, user.tenant_id)
    end
  end

  describe "authorize_role_in_tenant/3" do
    test "owner can access owner/admin/agent scopes" do
      user = insert(:user, role: "owner")
      tenant_id = user.tenant_id

      assert :ok = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin))
      assert :ok = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin agent))
      assert :ok = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner))
    end

    test "agent is forbidden from owner/admin-only actions" do
      user = insert(:user, role: "agent")
      tenant_id = user.tenant_id

      assert {:error, :forbidden} = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin))
      assert :ok = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin agent))
    end

    test "viewer is forbidden from all write actions" do
      user = insert(:user, role: "viewer")
      tenant_id = user.tenant_id

      assert {:error, :forbidden} = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin))
      assert {:error, :forbidden} = Policy.authorize_role_in_tenant(user, tenant_id, ~w(owner admin agent))
    end

    test "user from wrong tenant is unauthorized regardless of role" do
      user = insert(:user, role: "owner")
      other_tenant = insert(:tenant)

      assert {:error, :unauthorized} =
               Policy.authorize_role_in_tenant(user, other_tenant.id, ~w(owner admin))
    end
  end

  describe "can_manage_*/2 helpers" do
    setup do
      %{tenant: insert(:tenant)}
    end

    test "can_manage_onboarding? — only owner and admin", %{tenant: tenant} do
      owner = insert(:user, tenant: tenant, role: "owner")
      admin = insert(:user, tenant: tenant, role: "admin")
      agent = insert(:user, tenant: tenant, role: "agent")
      viewer = insert(:user, tenant: tenant, role: "viewer")

      assert Policy.can_manage_onboarding?(owner, tenant.id)
      assert Policy.can_manage_onboarding?(admin, tenant.id)
      refute Policy.can_manage_onboarding?(agent, tenant.id)
      refute Policy.can_manage_onboarding?(viewer, tenant.id)
    end

    test "can_manage_conversations? — owner, admin, and agent", %{tenant: tenant} do
      owner = insert(:user, tenant: tenant, role: "owner")
      agent = insert(:user, tenant: tenant, role: "agent")
      viewer = insert(:user, tenant: tenant, role: "viewer")

      assert Policy.can_manage_conversations?(owner, tenant.id)
      assert Policy.can_manage_conversations?(agent, tenant.id)
      refute Policy.can_manage_conversations?(viewer, tenant.id)
    end
  end
end
