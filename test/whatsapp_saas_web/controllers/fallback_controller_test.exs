defmodule WhatsappSaasWeb.FallbackControllerTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaasWeb.FallbackController

  describe "call/2" do
    test "renders 404 for :not_found" do
      conn = FallbackController.call(build_conn(), {:error, :not_found})

      assert conn.status == 404
      assert %{"errors" => %{"detail" => "Not Found"}} == Jason.decode!(conn.resp_body)
    end

    test "renders 401 for :unauthorized" do
      conn = FallbackController.call(build_conn(), {:error, :unauthorized})

      assert conn.status == 401
      assert %{"errors" => %{"detail" => "Unauthorized"}} == Jason.decode!(conn.resp_body)
    end

    test "renders 403 for :forbidden" do
      conn = FallbackController.call(build_conn(), {:error, :forbidden})

      assert conn.status == 403
      assert %{"errors" => %{"detail" => "Forbidden"}} == Jason.decode!(conn.resp_body)
    end

    test "renders 400 for unknown atom errors" do
      conn = FallbackController.call(build_conn(), {:error, :plan_limit_reached})

      assert conn.status == 400
      assert %{"error" => "plan_limit_reached"} == Jason.decode!(conn.resp_body)
    end

    test "renders 422 for changeset errors" do
      tenant = insert(:tenant)

      changeset = WhatsappSaas.Tenants.Tenant.changeset(tenant, %{name: nil, slug: nil})
      changeset = %{changeset | action: :update}

      conn = FallbackController.call(build_conn(), {:error, changeset})

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "errors")
    end
  end

  defp build_conn do
    Plug.Test.conn(:get, "/")
  end
end
