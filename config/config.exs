# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :whatsapp_saas,
  ecto_repos: [WhatsappSaas.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :whatsapp_saas, Oban,
  repo: WhatsappSaas.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [webhooks: 25]

config :hammer,
  backend: {Hammer.Backend.ETS,
   [expiry_ms: 60_000 * 5, cleanup_interval_ms: 60_000 * 2]}

# Configures the endpoint
config :whatsapp_saas, WhatsappSaasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: WhatsappSaasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WhatsappSaas.PubSub,
  live_view: [signing_salt: "YToO0dHb"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Redact sensitive fields from logs
config :phoenix, :filter_parameters, [
  "password",
  "hashed_password",
  "secret",
  "token",
  "api_key",
  "signature"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
