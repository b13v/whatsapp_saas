defmodule WhatsappSaas.Repo do
  use Ecto.Repo,
    otp_app: :whatsapp_saas,
    adapter: Ecto.Adapters.Postgres
end
