defmodule WhatsappSaasWeb.OnboardingController do
  @moduledoc """
  Minimal callback surface for WhatsApp onboarding redirects.
  """

  use Phoenix.Controller, formats: [:json, :html], layouts: []

  alias WhatsappSaas.Onboarding.CallbackHandler

  def show(conn, params) do
    case CallbackHandler.handle_callback(params) do
      {:ok, %{status: status, session: session}} ->
        json(conn, %{
          status: Atom.to_string(status),
          onboarding_session_id: session.id,
          external_setup_id: session.external_setup_id
        })

      {:error, :session_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "not_found"})

      {:error, :invalid_state_transition} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{status: "invalid_state_transition"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", error: inspect(reason)})
    end
  end
end
