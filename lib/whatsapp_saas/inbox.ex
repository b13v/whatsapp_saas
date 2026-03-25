defmodule WhatsappSaas.Inbox do
  @moduledoc """
  Conversation and message domain logic.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Contacts
  alias WhatsappSaas.Inbox.{Conversation, Message}
  alias WhatsappSaas.Repo
  alias WhatsappSaas.WhatsApp
  alias WhatsappSaas.WhatsApp.Template

  @message_status_order %{
    "queued" => 0,
    "sent" => 1,
    "delivered" => 2,
    "read" => 3,
    "failed" => 4
  }

  def list_conversations(actor, tenant_id) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      Conversation
      |> where([conversation], conversation.tenant_id == ^tenant_id)
      |> order_by([conversation],
        desc: conversation.last_message_at,
        desc: conversation.inserted_at
      )
      |> Repo.all()
    end
  end

  def get_conversation(actor, conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      %Conversation{} = conversation ->
        with :ok <- Policy.authorize_tenant_access(actor, conversation.tenant_id),
             do: {:ok, conversation}

      nil ->
        {:error, :not_found}
    end
  end

  def get_conversation!(actor, conversation_id) do
    case get_conversation(actor, conversation_id) do
      {:ok, conversation} -> conversation
      _ -> raise Ecto.NoResultsError, queryable: Conversation
    end
  end

  def get_or_create_open_conversation(tenant_id, whatsapp_account_id, contact_id) do
    conversation =
      Conversation
      |> where(
        [conversation],
        conversation.tenant_id == ^tenant_id and
          conversation.whatsapp_account_id == ^whatsapp_account_id and
          conversation.contact_id == ^contact_id and
          conversation.status in ["open", "waiting"]
      )
      |> order_by([conversation], desc: conversation.inserted_at)
      |> limit(1)
      |> Repo.one()

    case conversation do
      %Conversation{} = conversation ->
        {:ok, conversation}

      nil ->
        %Conversation{}
        |> Conversation.changeset(%{
          tenant_id: tenant_id,
          whatsapp_account_id: whatsapp_account_id,
          contact_id: contact_id,
          status: "open",
          unread_count: 0
        })
        |> Repo.insert()
    end
  end

  def assign_conversation(actor, %Conversation{} = conversation, assigned_user_id) do
    with :ok <-
           Policy.authorize_role_in_tenant(actor, conversation.tenant_id, ~w(owner admin agent)) do
      Multi.new()
      |> Multi.update(
        :conversation,
        Conversation.changeset(conversation, %{assigned_user_id: assigned_user_id})
      )
      |> Multi.insert(:audit_log, fn %{conversation: updated_conversation} ->
        WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
          tenant_id: updated_conversation.tenant_id,
          actor_user_id: actor.id,
          action: "conversation_assigned",
          entity_type: "conversation",
          entity_id: updated_conversation.id,
          payload: %{assigned_user_id: updated_conversation.assigned_user_id}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{conversation: updated_conversation}} -> {:ok, updated_conversation}
        {:error, :conversation, changeset, _changes} -> {:error, changeset}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  def close_conversation(actor, %Conversation{} = conversation) do
    with :ok <-
           Policy.authorize_role_in_tenant(actor, conversation.tenant_id, ~w(owner admin agent)) do
      update_conversation_status(actor, conversation, "closed", "conversation_closed", %{
        closed_at: DateTime.utc_now()
      })
    end
  end

  def reopen_conversation(actor, %Conversation{} = conversation) do
    with :ok <-
           Policy.authorize_role_in_tenant(actor, conversation.tenant_id, ~w(owner admin agent)) do
      update_conversation_status(actor, conversation, "open", "conversation_reopened", %{
        closed_at: nil
      })
    end
  end

  def list_messages(actor, conversation_id) do
    with {:ok, conversation} <- get_conversation(actor, conversation_id) do
      Message
      |> where([message], message.conversation_id == ^conversation.id)
      |> order_by([message], asc: message.inserted_at)
      |> Repo.all()
    end
  end

  def create_outgoing_message(%Conversation{} = conversation, attrs) do
    message_attrs =
      attrs
      |> Map.new()
      |> Map.put(:tenant_id, conversation.tenant_id)
      |> Map.put(:conversation_id, conversation.id)
      |> Map.put(:whatsapp_account_id, conversation.whatsapp_account_id)
      |> Map.put(:contact_id, conversation.contact_id)
      |> Map.put_new(:direction, "outbound")
      |> Map.put_new(:status, "queued")

    %Message{}
    |> Message.changeset(message_attrs)
    |> Repo.insert()
  end

  def mark_message_sent(%Message{} = message, attrs \\ %{}) do
    message
    |> Message.changeset(
      Map.merge(%{status: "sent", sent_at: DateTime.utc_now()}, Map.new(attrs))
    )
    |> Repo.update()
  end

  def mark_message_delivered(%Message{} = message, attrs \\ %{}) do
    message
    |> Message.changeset(
      Map.merge(%{status: "delivered", delivered_at: DateTime.utc_now()}, Map.new(attrs))
    )
    |> Repo.update()
  end

  def mark_message_read(%Message{} = message, attrs \\ %{}) do
    message
    |> Message.changeset(
      Map.merge(%{status: "read", read_at: DateTime.utc_now()}, Map.new(attrs))
    )
    |> Repo.update()
  end

  def mark_message_failed(%Message{} = message, attrs \\ %{}) do
    message
    |> Message.changeset(
      Map.merge(%{status: "failed", failed_at: DateTime.utc_now()}, Map.new(attrs))
    )
    |> Repo.update()
  end

  def get_message_by_provider_message_id(provider_message_id)
      when is_binary(provider_message_id) do
    Message
    |> where([message], message.provider_message_id == ^provider_message_id)
    |> Repo.one()
    |> case do
      %Message{} = message -> {:ok, message}
      nil -> {:error, :not_found}
    end
  end

  def get_message_by_provider_message_id(_provider_message_id), do: {:error, :not_found}

  def apply_provider_message_status(%Message{} = message, status, attrs \\ %{}) do
    attrs = Map.new(attrs)

    next_status =
      if status_rank(status) >= status_rank(message.status) do
        status
      else
        message.status
      end

    merged_attrs =
      attrs
      |> keep_present_values()
      |> ensure_status_timestamps(status)
      |> maybe_preserve_higher_state_timestamps(message)
      |> Map.put(:status, next_status)

    message
    |> Message.changeset(merged_attrs)
    |> Repo.update()
  end

  def record_inbound_message(tenant_id, normalized_payload) do
    message_payload = normalized_payload[:message] || normalized_payload["message"] || %{}

    with {:ok, existing_message} <-
           maybe_return_existing_inbound_message(tenant_id, message_payload) do
      {:ok, %{message: existing_message, duplicate?: true}}
    else
      {:error, :not_found} ->
        do_record_inbound_message(tenant_id, normalized_payload, message_payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_record_inbound_message(tenant_id, normalized_payload, message_payload) do
    with {:ok, contact} <- Contacts.upsert_contact_from_inbound(tenant_id, normalized_payload),
         {:ok, conversation} <-
           get_or_create_open_conversation(
             tenant_id,
             normalized_payload[:whatsapp_account_id] ||
               normalized_payload["whatsapp_account_id"],
             contact.id
           ),
         message_attrs <- %{
           tenant_id: tenant_id,
           conversation_id: conversation.id,
           whatsapp_account_id: conversation.whatsapp_account_id,
           contact_id: contact.id,
           direction: "inbound",
           kind: message_payload[:kind] || message_payload["kind"] || "text",
           provider_message_id:
             message_payload[:provider_message_id] || message_payload["provider_message_id"],
           body: message_payload[:body] || message_payload["body"],
           payload: message_payload[:payload] || message_payload["payload"] || %{},
           sent_at: message_payload[:sent_at] || message_payload["sent_at"],
           status: "delivered"
         } do
      Multi.new()
      |> Multi.insert(:message, Message.changeset(%Message{}, message_attrs))
      |> Multi.update(
        :conversation,
        Conversation.changeset(conversation, %{
          unread_count: conversation.unread_count + 1,
          last_message_at:
            message_payload[:sent_at] || message_payload["sent_at"] || DateTime.utc_now(),
          closed_at: nil,
          status: "open"
        })
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{message: message, conversation: updated_conversation}} ->
          {:ok, %{message: message, conversation: updated_conversation, contact: contact}}

        {:error, :message, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  defp maybe_return_existing_inbound_message(_tenant_id, message_payload) do
    provider_message_id =
      message_payload[:provider_message_id] || message_payload["provider_message_id"]

    case get_message_by_provider_message_id(provider_message_id) do
      {:ok, %Message{direction: "inbound"} = message} -> {:ok, message}
      {:ok, _message} -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp ensure_status_timestamps(attrs, "sent"),
    do: Map.put_new(attrs, :sent_at, DateTime.utc_now())

  defp ensure_status_timestamps(attrs, "delivered") do
    attrs
    |> Map.put_new(:delivered_at, DateTime.utc_now())
    |> Map.put_new(:sent_at, DateTime.utc_now())
  end

  defp ensure_status_timestamps(attrs, "read") do
    attrs
    |> Map.put_new(:read_at, DateTime.utc_now())
    |> Map.put_new(:delivered_at, DateTime.utc_now())
    |> Map.put_new(:sent_at, DateTime.utc_now())
  end

  defp ensure_status_timestamps(attrs, "failed"),
    do: Map.put_new(attrs, :failed_at, DateTime.utc_now())

  defp ensure_status_timestamps(attrs, _status), do: attrs

  defp maybe_preserve_higher_state_timestamps(attrs, %Message{} = message) do
    attrs
    |> Map.put_new(:sent_at, message.sent_at)
    |> Map.put_new(:delivered_at, message.delivered_at)
    |> Map.put_new(:read_at, message.read_at)
    |> Map.put_new(:failed_at, message.failed_at)
  end

  defp keep_present_values(attrs) do
    attrs
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp status_rank(status), do: Map.get(@message_status_order, status, -1)

  def send_text_reply(actor, %Conversation{} = conversation, attrs) do
    with :ok <-
           Policy.authorize_role_in_tenant(actor, conversation.tenant_id, ~w(owner admin agent)),
         {:ok, message} <-
           create_outgoing_message(conversation, Map.put(Map.new(attrs), :kind, "text")),
         account <- WhatsApp.get_account!(actor, conversation.whatsapp_account_id),
         {:ok, provider} <- WhatsApp.provider_module_for_account(account),
         {:ok, response} <-
           provider.send_text_message(%{
             account: account,
             conversation: conversation,
             body: Map.get(attrs, :body) || Map.get(attrs, "body"),
             payload: Map.get(attrs, :payload) || Map.get(attrs, "payload") || %{}
           }) do
      mark_message_sent(message, %{
        provider_message_id: response.provider_message_id,
        payload: response.payload
      })
    else
      {:error, reason} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  def send_template_message(actor, %Conversation{} = conversation, attrs) do
    with :ok <-
           Policy.authorize_role_in_tenant(actor, conversation.tenant_id, ~w(owner admin agent)),
         %Template{} = template <-
           WhatsApp.get_template!(
             actor,
             Map.get(attrs, :template_id) || Map.fetch!(attrs, "template_id")
           ),
         true <- template.tenant_id == conversation.tenant_id,
         {:ok, message} <-
           create_outgoing_message(conversation, Map.put(Map.new(attrs), :kind, "template")),
         account <- WhatsApp.get_account!(actor, conversation.whatsapp_account_id),
         {:ok, provider} <- WhatsApp.provider_module_for_account(account),
         {:ok, response} <-
           provider.send_template_message(%{
             account: account,
             conversation: conversation,
             template: template,
             payload: Map.get(attrs, :payload) || Map.get(attrs, "payload") || %{}
           }) do
      mark_message_sent(message, %{
        provider_message_id: response.provider_message_id,
        payload: response.payload
      })
    else
      false -> {:error, :template_tenant_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_conversation_status(actor, conversation, status, audit_action, attrs) do
    Multi.new()
    |> Multi.update(
      :conversation,
      Conversation.changeset(conversation, Map.put(Map.new(attrs), :status, status))
    )
    |> Multi.insert(:audit_log, fn %{conversation: updated_conversation} ->
      WhatsappSaas.Audit.AuditLog.changeset(%WhatsappSaas.Audit.AuditLog{}, %{
        tenant_id: updated_conversation.tenant_id,
        actor_user_id: actor.id,
        action: audit_action,
        entity_type: "conversation",
        entity_id: updated_conversation.id,
        payload: %{status: updated_conversation.status}
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{conversation: updated_conversation}} -> {:ok, updated_conversation}
      {:error, :conversation, changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end
