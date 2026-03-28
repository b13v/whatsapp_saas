defmodule WhatsappSaas.Contacts do
  @moduledoc """
  Contact and consent domain logic.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Contacts.{Contact, ContactConsent}
  alias WhatsappSaas.Repo

  def list_contacts(actor, tenant_id, opts \\ []) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      Contact
      |> where([contact], contact.tenant_id == ^tenant_id)
      |> order_by([contact], asc: contact.name, asc: contact.phone_e164)
      |> paginate(opts)
      |> Repo.all()
    end
  end

  def get_contact(actor, contact_id) do
    case Repo.get(Contact, contact_id) do
      %Contact{} = contact ->
        with :ok <- Policy.authorize_tenant_access(actor, contact.tenant_id), do: {:ok, contact}

      nil ->
        {:error, :not_found}
    end
  end

  def get_contact!(actor, contact_id) do
    case get_contact(actor, contact_id) do
      {:ok, contact} -> contact
      _ -> raise Ecto.NoResultsError, queryable: Contact
    end
  end

  def get_contact_by_phone(tenant_id, phone_e164) do
    Contact
    |> where([contact], contact.tenant_id == ^tenant_id and contact.phone_e164 == ^phone_e164)
    |> Repo.one()
    |> case do
      %Contact{} = contact -> {:ok, contact}
      nil -> {:error, :not_found}
    end
  end

  def create_contact(actor, attrs) do
    tenant_id = fetch_tenant_id!(attrs)

    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      %Contact{}
      |> Contact.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_contact(actor, %Contact{} = contact, attrs) do
    with :ok <- Policy.authorize_tenant_access(actor, contact.tenant_id) do
      contact
      |> Contact.changeset(attrs)
      |> Repo.update()
    end
  end

  def upsert_contact_from_inbound(tenant_id, normalized_payload) do
    phone_e164 =
      get_in(normalized_payload, [:phone_e164]) || get_in(normalized_payload, ["phone_e164"])

    attrs = %{
      tenant_id: tenant_id,
      phone_e164: phone_e164,
      external_wa_id: normalized_payload[:external_wa_id] || normalized_payload["external_wa_id"],
      name: normalized_payload[:contact_name] || normalized_payload["contact_name"],
      last_seen_at:
        normalized_payload[:last_seen_at] || normalized_payload["last_seen_at"] ||
          DateTime.utc_now()
    }

    case Repo.get_by(Contact, tenant_id: tenant_id, phone_e164: phone_e164) do
      %Contact{} = contact ->
        merged_attrs =
          attrs
          |> Enum.reject(fn {key, value} ->
            is_nil(value) or (key == :name and not is_nil(contact.name))
          end)
          |> Map.new()

        contact
        |> Contact.changeset(merged_attrs)
        |> Repo.update()

      nil ->
        %Contact{}
        |> Contact.changeset(attrs)
        |> Repo.insert()
    end
  end

  def update_opt_in_status(%Contact{} = contact, status, proof_attrs \\ %{}) do
    consent_attrs =
      case status do
        "subscribed" ->
          %{
            tenant_id: contact.tenant_id,
            contact_id: contact.id,
            channel: "whatsapp",
            source: Map.get(proof_attrs, :source) || Map.get(proof_attrs, "source"),
            granted_at: DateTime.utc_now(),
            proof: Map.get(proof_attrs, :proof) || Map.get(proof_attrs, "proof") || %{}
          }

        "unsubscribed" ->
          %{
            tenant_id: contact.tenant_id,
            contact_id: contact.id,
            channel: "whatsapp",
            source: Map.get(proof_attrs, :source) || Map.get(proof_attrs, "source"),
            revoked_at: DateTime.utc_now(),
            proof: Map.get(proof_attrs, :proof) || Map.get(proof_attrs, "proof") || %{}
          }

        _ ->
          nil
      end

    Multi.new()
    |> Multi.update(
      :contact,
      Contact.changeset(contact, %{
        opt_in_status: status,
        opted_in_at:
          if(status == "subscribed", do: DateTime.utc_now(), else: contact.opted_in_at),
        unsubscribed_at:
          if(status == "unsubscribed", do: DateTime.utc_now(), else: contact.unsubscribed_at)
      })
    )
    |> maybe_insert_consent(consent_attrs)
    |> Repo.transaction()
    |> case do
      {:ok, %{contact: updated_contact}} -> {:ok, updated_contact}
      {:error, :contact, changeset, _changes} -> {:error, changeset}
      {:error, :contact_consent, changeset, _changes} -> {:error, changeset}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def tag_contact(%Contact{} = contact, tag, value \\ true) do
    tags = Map.put(contact.tags || %{}, tag, value)
    contact |> Contact.changeset(%{tags: tags}) |> Repo.update()
  end

  def untag_contact(%Contact{} = contact, tag, _value \\ nil) do
    tags = Map.delete(contact.tags || %{}, tag)
    contact |> Contact.changeset(%{tags: tags}) |> Repo.update()
  end

  @doc """
  Returns contacts matching an audience filter mode for campaign targeting.
  """
  def list_contacts_for_audience(tenant_id, mode) do
    query =
      case mode do
        "tagged_returning" ->
          from(contact in Contact,
            where: contact.tenant_id == ^tenant_id,
            where: fragment("? ->> 'returning' = 'true'", contact.tags)
          )

        "subscribed" ->
          from(contact in Contact,
            where: contact.tenant_id == ^tenant_id and contact.opt_in_status == "subscribed"
          )

        _ ->
          from(contact in Contact, where: contact.tenant_id == ^tenant_id)
      end

    {:ok, Repo.all(query)}
  end

  defp maybe_insert_consent(multi, nil), do: multi

  defp maybe_insert_consent(multi, attrs) do
    Multi.insert(multi, :contact_consent, ContactConsent.changeset(%ContactConsent{}, attrs))
  end

  defp fetch_tenant_id!(attrs) do
    Map.get(attrs, :tenant_id) || Map.fetch!(attrs, "tenant_id")
  end

  @default_page_size 50

  defp paginate(query, opts) do
    limit = Keyword.get(opts, :limit, @default_page_size)
    offset = Keyword.get(opts, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end
end
