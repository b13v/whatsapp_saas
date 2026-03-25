defmodule WhatsappSaas.Onboarding.CallbackHandler do
  @moduledoc """
  Minimal redirect callback handling for onboarding providers.
  """

  alias WhatsappSaas.Onboarding
  alias WhatsappSaas.Onboarding.OnboardingSession

  @spec handle_callback(map()) ::
          {:ok, %{status: atom(), session: OnboardingSession.t()}}
          | {:error, :session_not_found | :invalid_state_transition | term()}
  def handle_callback(params) do
    case Onboarding.mark_callback_received(params) do
      {:ok, %OnboardingSession{} = session} ->
        {:ok, %{status: callback_status(session), session: session}}

      {:error, :not_found} ->
        {:error, :session_not_found}

      {:error, :session_not_found} = error ->
        error

      {:error, _reason} = error ->
        error
    end
  end

  defp callback_status(%OnboardingSession{state: "connected"}), do: :connected
  defp callback_status(%OnboardingSession{state: "failed"}), do: :failed
  defp callback_status(_session), do: :pending
end
