defmodule WhatsappSaas.WhatsApp do
  @moduledoc """
  Internal boundary for WhatsApp accounts, templates, and provider dispatch.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias WhatsappSaas.Accounts.Policy
  alias WhatsappSaas.Repo
  alias WhatsappSaas.WhatsApp.{ProviderRegistry, Template, WhatsappAccount}

  @doc """
  Resolves a provider name to its adapter module.
  """
  def provider_module(provider), do: ProviderRegistry.provider_module(provider)

  def provider_module_for_account(%WhatsappAccount{provider: provider}),
    do: ProviderRegistry.provider_module(provider)

  def find_account_by_provider_hints(provider, hints) do
    hints = Map.new(hints)

    external_account_id =
      Map.get(hints, :external_account_id) || Map.get(hints, "external_account_id")

    external_phone_number_id =
      Map.get(hints, :external_phone_number_id) || Map.get(hints, "external_phone_number_id")

    external_waba_id = Map.get(hints, :external_waba_id) || Map.get(hints, "external_waba_id")

    identifiers = [
      {:external_account_id, external_account_id},
      {:external_phone_number_id, external_phone_number_id},
      {:external_waba_id, external_waba_id}
    ]

    if Enum.any?(identifiers, fn {_field, value} -> is_binary(value) and value != "" end) do
      dynamic =
        Enum.reduce(identifiers, false, fn
          {_field, value}, acc when is_nil(value) or value == "" ->
            acc

          {field, value}, false ->
            dynamic([account], field(account, ^field) == ^value)

          {field, value}, acc ->
            dynamic([account], ^acc or field(account, ^field) == ^value)
        end)

      query =
        WhatsappAccount
        |> where([account], account.provider == ^to_string(provider))
        |> where(^dynamic)
        |> order_by([account], desc: account.connected_at, desc: account.inserted_at)
        |> limit(1)

      case Repo.one(query) do
        %WhatsappAccount{} = account -> {:ok, account}
        nil -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  @spec get_account(struct(), Ecto.UUID.t()) ::
          {:ok, WhatsappAccount.t()} | {:error, atom()}
  def get_account(actor, account_id) do
    case Repo.get(WhatsappAccount, account_id) do
      %WhatsappAccount{} = account ->
        with :ok <- Policy.authorize_tenant_access(actor, account.tenant_id) do
          {:ok, account}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def get_account!(actor, account_id) do
    case get_account(actor, account_id) do
      {:ok, account} -> account
      _ -> raise Ecto.NoResultsError, queryable: WhatsappAccount
    end
  end

  def list_accounts_for_tenant(actor, tenant_id) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      WhatsappAccount
      |> where([account], account.tenant_id == ^tenant_id)
      |> order_by([account], asc: account.inserted_at)
      |> Repo.all()
    end
  end

  def create_account(actor, attrs) do
    tenant_id = fetch_tenant_id!(attrs)

    with :ok <- Policy.authorize_role_in_tenant(actor, tenant_id, ~w(owner admin)) do
      %WhatsappAccount{}
      |> WhatsappAccount.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_account(actor, %WhatsappAccount{} = account, attrs) do
    with :ok <- Policy.authorize_role_in_tenant(actor, account.tenant_id, ~w(owner admin)) do
      account
      |> WhatsappAccount.changeset(attrs)
      |> Repo.update()
    end
  end

  def upsert_account_from_provider(tenant_id, attrs) do
    external_account_id =
      Map.get(attrs, :external_account_id) || Map.get(attrs, "external_account_id")

    account =
      cond do
        external_account_id ->
          Repo.get_by(WhatsappAccount,
            tenant_id: tenant_id,
            external_account_id: external_account_id
          )

        Map.get(attrs, :external_phone_number_id) || Map.get(attrs, "external_phone_number_id") ->
          Repo.get_by(WhatsappAccount,
            tenant_id: tenant_id,
            external_phone_number_id:
              Map.get(attrs, :external_phone_number_id) ||
                Map.get(attrs, "external_phone_number_id")
          )

        Map.get(attrs, :external_waba_id) || Map.get(attrs, "external_waba_id") ->
          Repo.get_by(WhatsappAccount,
            tenant_id: tenant_id,
            external_waba_id:
              Map.get(attrs, :external_waba_id) || Map.get(attrs, "external_waba_id")
          )

        true ->
          nil
      end

    changeset_attrs = Map.put(Map.new(attrs), :tenant_id, tenant_id)

    case account do
      %WhatsappAccount{} = account ->
        account |> WhatsappAccount.changeset(changeset_attrs) |> Repo.update()

      nil ->
        %WhatsappAccount{} |> WhatsappAccount.changeset(changeset_attrs) |> Repo.insert()
    end
  end

  def mark_account_connected(%WhatsappAccount{} = account, attrs \\ %{}) do
    update_attrs =
      attrs
      |> Map.new()
      |> Map.put(:status, "connected")
      |> Map.put_new(:connected_at, DateTime.utc_now())

    account
    |> WhatsappAccount.changeset(update_attrs)
    |> Repo.update()
  end

  def mark_account_disconnected(%WhatsappAccount{} = account, attrs \\ %{}) do
    account
    |> WhatsappAccount.changeset(Map.put(Map.new(attrs), :status, "disconnected"))
    |> Repo.update()
  end

  def list_templates(actor, tenant_id) do
    with :ok <- Policy.authorize_tenant_access(actor, tenant_id) do
      Template
      |> where([template], template.tenant_id == ^tenant_id)
      |> order_by([template], asc: template.name, asc: template.language)
      |> Repo.all()
    end
  end

  def get_template!(actor, template_id) do
    template = Repo.get!(Template, template_id)

    case Policy.authorize_tenant_access(actor, template.tenant_id) do
      :ok -> template
      _ -> raise Ecto.NoResultsError, queryable: Template
    end
  end

  def upsert_template(tenant_id, attrs) do
    template_attrs = Map.put(Map.new(attrs), :tenant_id, tenant_id)

    template =
      Repo.get_by(
        Template,
        tenant_id: tenant_id,
        whatsapp_account_id: Map.get(template_attrs, :whatsapp_account_id),
        name: Map.get(template_attrs, :name),
        language: Map.get(template_attrs, :language)
      )

    case template do
      %Template{} = template ->
        template |> Template.changeset(template_attrs) |> Repo.update()

      nil ->
        %Template{} |> Template.changeset(template_attrs) |> Repo.insert()
    end
  end

  def sync_templates(actor, %WhatsappAccount{} = account) do
    with :ok <- Policy.authorize_role_in_tenant(actor, account.tenant_id, ~w(owner admin)),
         provider when is_atom(provider) <- provider_module_for_account(account),
         {:ok, templates} <- provider.list_templates(%{account: account}) do
      Multi.new()
      |> Multi.run(:templates, fn _repo, _changes ->
        Enum.reduce_while(templates, {:ok, []}, fn template_attrs, {:ok, acc} ->
          case upsert_template(
                 account.tenant_id,
                 Map.put(template_attrs, :whatsapp_account_id, account.id)
               ) do
            {:ok, template} -> {:cont, {:ok, [template | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
        |> case do
          {:ok, synced} -> {:ok, Enum.reverse(synced)}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{templates: synced}} -> {:ok, synced}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
      provider_error -> provider_error
    end
  end

  defp fetch_tenant_id!(attrs) do
    Map.get(attrs, :tenant_id) || Map.fetch!(attrs, "tenant_id")
  end
end
