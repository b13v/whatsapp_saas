defmodule WhatsappSaas.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhatsappSaasWeb.Telemetry,
      WhatsappSaas.Repo,
      {DNSCluster, query: Application.get_env(:whatsapp_saas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WhatsappSaas.PubSub},
      # Start a worker by calling: WhatsappSaas.Worker.start_link(arg)
      # {WhatsappSaas.Worker, arg},
      # Start to serve requests, typically the last entry
      WhatsappSaasWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WhatsappSaas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhatsappSaasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
