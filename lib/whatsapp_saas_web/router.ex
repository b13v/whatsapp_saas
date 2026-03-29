defmodule WhatsappSaasWeb.Router do
  use WhatsappSaasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook do
    plug :accepts, ["json"]
    plug WhatsappSaasWeb.Plugs.RateLimiter, scale: 60_000, limit: 200
  end

  pipeline :onboarding do
    plug :accepts, ["json"]
    plug WhatsappSaasWeb.Plugs.RateLimiter, scale: 60_000, limit: 20
  end

  scope "/api", WhatsappSaasWeb do
    pipe_through :api
  end

  scope "/", WhatsappSaasWeb do
    pipe_through :onboarding
    get "/whatsapp/onboarding/callback", OnboardingController, :show
  end

  scope "/", WhatsappSaasWeb do
    pipe_through :webhook
    post "/webhooks/whatsapp/kapso", WhatsAppWebhookController, :kapso
  end
end
