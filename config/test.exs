import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :whatsapp_saas, WhatsappSaas.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "whatsapp_saas_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :whatsapp_saas, WhatsappSaasWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "RN/Un5SwQMTAFznlpx7g58xG9UgDq03eyd7YHFLuWU1lyVNkE6FIvf/r1ba2oDXQ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :whatsapp_saas, Oban,
  repo: WhatsappSaas.Repo,
  plugins: false,
  queues: false,
  testing: :manual

config :whatsapp_saas, WhatsappSaas.Webhooks.SignatureVerifier,
  kapso_signature_secret: "test-secret-key-for-webhook-verification"
