defmodule WhatsappSaas.AccountsTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Accounts

  describe "invite_user_to_tenant/3" do
    test "owner can invite a new user" do
      %{tenant: tenant, user: owner} = tenant_with_user(role: "owner")

      assert {:ok, user} =
               Accounts.invite_user_to_tenant(owner, tenant.id, %{
                 email: "invited@example.com",
                 full_name: "Invited User",
                 role: "agent"
               })

      assert user.email == "invited@example.com"
      assert user.role == "agent"
      assert user.status == "invited"
      assert user.tenant_id == tenant.id
      assert byte_size(user.hashed_password) > 20
    end

    test "defaults role to agent when not specified" do
      %{tenant: tenant, user: owner} = tenant_with_user(role: "owner")

      assert {:ok, user} =
               Accounts.invite_user_to_tenant(owner, tenant.id, %{
                 email: "default-role@example.com"
               })

      assert user.role == "agent"
    end

    test "agent cannot invite users" do
      %{tenant: tenant, user: agent} = tenant_with_user(role: "agent")

      assert {:error, :forbidden} =
               Accounts.invite_user_to_tenant(agent, tenant.id, %{
                 email: "nope@example.com"
               })
    end

    test "owner from different tenant cannot invite" do
      %{tenant: tenant} = tenant_with_user(role: "owner")
      %{user: other_owner} = tenant_with_user(role: "owner")

      assert {:error, :unauthorized} =
               Accounts.invite_user_to_tenant(other_owner, tenant.id, %{
                 email: "cross-tenant@example.com"
               })
    end
  end

  describe "update_user_role/4" do
    test "owner can update user role" do
      %{tenant: tenant, user: owner} = tenant_with_user(role: "owner")
      target = insert(:user, tenant: tenant, role: "agent")

      assert {:ok, updated} = Accounts.update_user_role(owner, target, tenant.id, "admin")
      assert updated.role == "admin"
    end

    test "admin can update user role within tenant" do
      %{tenant: tenant, user: admin} = tenant_with_user(role: "admin")
      target = insert(:user, tenant: tenant, role: "agent")

      assert {:ok, updated} = Accounts.update_user_role(admin, target, tenant.id, "admin")
      assert updated.role == "admin"
    end

    test "cannot change role of user in different tenant" do
      %{tenant: tenant, user: owner} = tenant_with_user(role: "owner")
      %{user: other_user} = tenant_with_user(role: "agent")

      assert {:error, :unauthorized} =
               Accounts.update_user_role(owner, other_user, tenant.id, "admin")
    end
  end

  describe "disable_user/3" do
    test "owner can disable a user" do
      %{tenant: tenant, user: owner} = tenant_with_user(role: "owner")
      target = insert(:user, tenant: tenant, role: "agent")

      assert {:ok, disabled} = Accounts.disable_user(owner, target, tenant.id)
      assert disabled.status == "disabled"
    end

    test "agent cannot disable users" do
      %{tenant: tenant, user: agent} = tenant_with_user(role: "agent")
      target = insert(:user, tenant: tenant, role: "viewer")

      assert {:error, :forbidden} = Accounts.disable_user(agent, target, tenant.id)
    end
  end
end
