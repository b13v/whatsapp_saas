defmodule WhatsappSaas.MigrationFoundationTest do
  use WhatsappSaas.DataCase, async: false

  describe "migration foundation" do
    test "creates the tenant and user tables needed for multi-tenancy" do
      assert table_exists?("tenants")
      assert table_exists?("users")

      assert columns_for("users") |> Enum.member?("tenant_id")
      assert columns_for("users") |> Enum.member?("role")
      assert columns_for("users") |> Enum.member?("full_name")
      assert columns_for("users") |> Enum.member?("status")
    end

    test "creates the domain tables and critical unique indexes" do
      for table <- ~w(
            whatsapp_accounts
            onboarding_sessions
            contacts
            conversations
            messages
            templates
            campaigns
            campaign_deliveries
            webhook_events
            audit_logs
            usage_counters
            contact_consents
          ) do
        assert table_exists?(table), "expected #{table} table to exist"
      end

      assert index_exists?("tenants_slug_index")
      assert index_exists?("contacts_tenant_id_phone_e164_index")
      assert index_exists?("templates_tenant_account_name_language_index")
      assert index_exists?("campaign_deliveries_campaign_id_contact_id_index")
      assert index_exists?("usage_counters_tenant_id_metric_date_index")
    end
  end

  defp table_exists?(table_name) do
    %{rows: [[exists?]]} =
      Repo.query!("SELECT to_regclass($1) IS NOT NULL", ["public.#{table_name}"])

    exists?
  end

  defp columns_for(table_name) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1
        ORDER BY ordinal_position
        """,
        [table_name]
      )

    Enum.map(rows, &List.first/1)
  end

  defp index_exists?(index_name) do
    %{rows: [[exists?]]} =
      Repo.query!("SELECT to_regclass($1) IS NOT NULL", ["public.#{index_name}"])

    exists?
  end
end
