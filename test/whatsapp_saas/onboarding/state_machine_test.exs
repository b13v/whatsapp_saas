defmodule WhatsappSaas.Onboarding.StateMachineTest do
  use WhatsappSaas.DataCase, async: true

  alias WhatsappSaas.Onboarding.StateMachine

  describe "states/0" do
    test "returns all valid states" do
      states = StateMachine.states()

      assert "created" in states
      assert "link_generated" in states
      assert "callback_received" in states
      assert "connected" in states
      assert "failed" in states
    end
  end

  describe "valid_state?/1" do
    test "accepts known states" do
      assert StateMachine.valid_state?("created")
      assert StateMachine.valid_state?("connected")
      assert StateMachine.valid_state?("failed")
    end

    test "rejects unknown states" do
      refute StateMachine.valid_state?("unknown_state")
      refute StateMachine.valid_state?("")
      refute StateMachine.valid_state?("pending")
    end
  end

  describe "transition/2" do
    test "created -> link_generated" do
      assert {:ok, "link_generated"} = StateMachine.transition("created", "link_generated")
    end

    test "link_generated -> callback_received" do
      assert {:ok, "callback_received"} =
               StateMachine.transition("link_generated", "callback_received")
    end

    test "callback_received -> connected" do
      assert {:ok, "connected"} =
               StateMachine.transition("callback_received", "connected")
    end

    test "any state -> failed" do
      assert {:ok, "failed"} = StateMachine.transition("created", "failed")
      assert {:ok, "failed"} = StateMachine.transition("link_generated", "failed")
      assert {:ok, "failed"} = StateMachine.transition("callback_received", "failed")
    end

    test "rejects invalid transitions" do
      assert {:error, :invalid_state_transition} =
               StateMachine.transition("created", "connected")

      assert {:error, :invalid_state_transition} =
               StateMachine.transition("connected", "created")
    end

    test "rejects transitions from terminal states" do
      assert {:error, :invalid_state_transition} =
               StateMachine.transition("connected", "link_generated")

      assert {:error, :invalid_state_transition} =
               StateMachine.transition("failed", "link_generated")
    end
  end
end
