defmodule WhatsappSaasWeb.Plugs.RateLimiterTest do
  use WhatsappSaasWeb.ConnCase, async: true

  alias WhatsappSaasWeb.Plugs.RateLimiter

  describe "rate limiting" do
    test "allows requests within the limit" do
      path = "/rl-allow-#{System.unique_integer([:positive])}"

      conn =
        build_conn(:get, path)
        |> RateLimiter.call(RateLimiter.init(scale: 60_000, limit: 5))

      refute conn.halted
    end

    test "blocks requests exceeding the limit and returns 429" do
      path = "/rl-block-#{System.unique_integer([:positive])}"
      opts = RateLimiter.init(scale: 60_000, limit: 2)

      conn1 = RateLimiter.call(build_conn(:get, path), opts)
      conn2 = RateLimiter.call(build_conn(:get, path), opts)
      refute conn1.halted
      refute conn2.halted

      conn3 = RateLimiter.call(build_conn(:get, path), opts)
      assert conn3.halted
      assert conn3.status == 429

      {:ok, body} = Jason.decode(conn3.resp_body)
      assert body == %{"error" => "rate_limit_exceeded"}
    end

    test "different paths use different buckets" do
      n = System.unique_integer([:positive])
      opts = RateLimiter.init(scale: 60_000, limit: 1)

      conn1 = RateLimiter.call(build_conn(:get, "/rl-bucket-a-#{n}"), opts)
      refute conn1.halted

      conn2 = RateLimiter.call(build_conn(:get, "/rl-bucket-b-#{n}"), opts)
      refute conn2.halted
    end
  end
end
