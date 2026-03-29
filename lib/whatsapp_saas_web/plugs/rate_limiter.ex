defmodule WhatsappSaasWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug using Hammer.

  Keyed by remote IP. Returns 429 with a JSON body when the limit is exceeded.

  ## Usage

      plug WhatsappSaasWeb.Plugs.RateLimiter,
        scale: 60_000,
        limit: 100

  `scale` is the time window in milliseconds. `limit` is the max requests
  allowed within that window.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      scale: Keyword.get(opts, :scale, 60_000),
      limit: Keyword.get(opts, :limit, 100),
      key_fn: Keyword.get(opts, :key_fn, &default_key/1)
    }
  end

  @impl true
  def call(conn, opts) do
    key = opts.key_fn.(conn)

    case Hammer.check_rate(key, opts.scale, opts.limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "rate_limit_exceeded"})
        |> halt()
    end
  end

  defp default_key(conn) do
    ip =
      conn.remote_ip
      |> :inet.ntoa()
      |> to_string()

    "rate_limit:#{ip}:#{conn.request_path}"
  end
end
