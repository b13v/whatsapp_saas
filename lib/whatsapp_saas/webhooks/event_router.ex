defmodule WhatsappSaas.Webhooks.EventRouter do
  @moduledoc """
  Maps normalized provider topics to webhook processor families.
  """

  @spec route(map()) :: {:ok, atom()} | {:error, :unsupported_topic}
  def route(%{topic: topic}) when topic in ["onboarding_update", "account_updated"],
    do: {:ok, :account}

  def route(%{"topic" => topic}) when topic in ["onboarding_update", "account_updated"],
    do: {:ok, :account}

  def route(%{topic: "template_updated"}), do: {:ok, :template}
  def route(%{"topic" => "template_updated"}), do: {:ok, :template}

  def route(%{topic: "inbound_message"}), do: {:ok, :message}
  def route(%{"topic" => "inbound_message"}), do: {:ok, :message}

  def route(%{topic: "message_status"}), do: {:ok, :message_status}
  def route(%{"topic" => "message_status"}), do: {:ok, :message_status}

  def route(_event), do: {:error, :unsupported_topic}
end
