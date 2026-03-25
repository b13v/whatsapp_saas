defmodule WhatsappSaasWeb.Router do
  use WhatsappSaasWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WhatsappSaasWeb do
    pipe_through :api
  end
end
