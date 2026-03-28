defmodule WhatsappSaasWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :whatsapp_saas

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_whatsapp_saas_key",
    signing_salt: "pi/UKiEq",
    same_site: "Lax",
    http_only: true,
    secure: Application.compile_env(:whatsapp_saas, :env) == :prod
  ]

  # socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :whatsapp_saas,
    gzip: false,
    only: WhatsappSaasWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :whatsapp_saas
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug :security_headers
  plug Plug.Session, @session_options
  plug WhatsappSaasWeb.Router

  @security_headers %{
    "x-frame-options" => "DENY",
    "x-content-type-options" => "nosniff",
    "x-xss-protection" => "1; mode=block",
    "referrer-policy" => "strict-origin-when-cross-origin"
  }

  defp security_headers(conn, _opts) do
    Enum.reduce(@security_headers, conn, fn {header, value}, acc ->
      Plug.Conn.put_resp_header(acc, header, value)
    end)
  end
end
