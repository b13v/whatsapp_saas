defmodule WhatsappSaas.Onboarding.StateMachine do
  @moduledoc """
  Explicit onboarding session state transitions.
  """

  @states ~w(created link_generated callback_received connected failed)
  @transitions %{
    "created" => MapSet.new(~w(link_generated failed)),
    "link_generated" => MapSet.new(~w(callback_received connected failed)),
    "callback_received" => MapSet.new(~w(connected failed)),
    "connected" => MapSet.new([]),
    "failed" => MapSet.new([])
  }

  @spec states() :: [String.t()]
  def states, do: @states

  @spec valid_state?(String.t()) :: boolean()
  def valid_state?(state), do: state in @states

  @spec transition(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_state_transition}
  def transition(from_state, to_state) when from_state == to_state and from_state in @states,
    do: {:ok, to_state}

  def transition(from_state, to_state) do
    if valid_state?(from_state) and valid_state?(to_state) and
         MapSet.member?(Map.fetch!(@transitions, from_state), to_state) do
      {:ok, to_state}
    else
      {:error, :invalid_state_transition}
    end
  end
end
