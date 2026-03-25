defmodule WhatsappSaas.WhatsApp.ProviderRegistry do
  @moduledoc """
  Single place for mapping provider identifiers to adapter modules.

  Future providers such as Meta-direct should plug in here without changing
  domain contexts.
  """

  alias WhatsappSaas.WhatsApp.WhatsappAccount

  @providers %{
    "kapso" => WhatsappSaas.WhatsApp.Providers.Kapso
  }

  @spec provider_module(String.t() | atom()) :: {:ok, module()} | {:error, :unknown_provider}
  def provider_module(provider) when is_atom(provider),
    do: provider |> Atom.to_string() |> provider_module()

  def provider_module(provider) when is_binary(provider) do
    case Map.get(@providers, provider) do
      nil -> {:error, :unknown_provider}
      module -> {:ok, module}
    end
  end

  @spec provider_module_for_account(WhatsappAccount.t()) ::
          {:ok, module()} | {:error, :unknown_provider}
  def provider_module_for_account(%WhatsappAccount{provider: provider}),
    do: provider_module(provider)
end
