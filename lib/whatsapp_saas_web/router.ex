defmodule WhatsappSaasWeb.Router do
  use WhatsappSaasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WhatsappSaasWeb do
    pipe_through :api
  end

  scope "/", WhatsappSaasWeb do
    get "/whatsapp/onboarding/callback", OnboardingController, :show
    post "/webhooks/whatsapp/kapso", WhatsAppWebhookController, :kapso
  end
end
