defmodule WhatsappSaas.WhatsApp.ProviderError do
  @moduledoc """
  Small helper for consistent provider-layer error tuples.
  """

  @spec config_missing(atom()) :: {:error, {:config_missing, atom()}}
  def config_missing(key), do: {:error, {:config_missing, key}}

  @spec request_failed(term()) :: {:error, {:provider_request_failed, term()}}
  def request_failed(reason), do: {:error, {:provider_request_failed, reason}}

  @spec normalization_failed(term()) :: {:error, {:normalization_failed, term()}}
  def normalization_failed(reason), do: {:error, {:normalization_failed, reason}}

  @spec unsupported_operation(atom()) :: {:error, {:unsupported_operation, atom()}}
  def unsupported_operation(operation), do: {:error, {:unsupported_operation, operation}}
end
