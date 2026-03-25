# WhatsApp Clinic SaaS Project Blueprint

## Goal

Build the MVP foundation for a multi-tenant SaaS product focused on onboarding dental clinics, medical clinics, and beauty salons to use WhatsApp for customer communications.

Each business tenant should be able to:

1. Sign up and create a workspace
2. Connect their WhatsApp business account through a provider-backed onboarding flow
3. Manage inbound and outbound customer conversations
4. Send approved templates such as appointment reminders and confirmations
5. Run simple campaigns and follow-ups

---

## Product Constraints

- This is **not** a generic omnichannel CRM
- This is a **WhatsApp-first SaaS** for clinics and beauty salons
- Prioritize:
  - onboarding
  - inbox
  - contacts
  - templates
  - appointment reminders
  - simple campaigns
- Keep implementation MVP-focused, production-minded, and easy to extend
- Use provider adapter architecture so the app can start with Kapso and later support direct Meta integration
- Use PostgreSQL for all durable state
- Use Oban for async processing
- Redis is not required
- Favor explicit schemas, clear boundaries, and robust webhook handling

---

## Technology Assumptions

- Elixir
- Phoenix
- Ecto
- PostgreSQL
- Oban
- JSON APIs are acceptable
- If UI files are needed, keep them minimal and functional
- Backend-first is preferred

---

## Domain and Business Context

Target customers:

- dental clinics
- medical clinics
- beauty salons

Typical WhatsApp use cases:

- appointment confirmation
- reminder 24h before visit
- reminder 2h before visit
- reschedule flow
- “we are ready for you” message
- follow-up after appointment
- promo / recall campaign to inactive clients
- inbound customer questions
- sending location / opening hours / service information

---

## Core Architecture Requirements

1. Multi-tenant shared-schema architecture with `tenant_id` on all tenant-owned tables
2. Clear Phoenix contexts
3. Provider adapter behaviour for WhatsApp infrastructure
4. Idempotent webhook ingestion
5. Oban workers for webhook/event processing and scheduled messaging
6. Role-based users per tenant
7. Auditability for key actions
8. Design for one VPS deployment initially

---

## Context Structure

Create or update the codebase to include these contexts:

- Accounts
- Tenants
- WhatsApp
- Onboarding
- Contacts
- Inbox
- Campaigns
- Audit
- Billing

### Responsibilities

#### Accounts
- tenant users
- roles: owner, admin, agent, viewer
- authentication integration hooks if needed

#### Tenants
- tenant/workspace creation
- tenant settings
- plan/status fields
- onboarding status summary

#### WhatsApp
- provider behaviour
- Kapso adapter
- account sync
- template sync
- send message / send template entrypoints

#### Onboarding
- create onboarding session
- generate setup link
- process callback/redirect
- reconcile with webhook-confirmed state

#### Contacts
- patient/customer contact records
- phone normalization
- opt-in status
- tags
- last interaction timestamps

#### Inbox
- conversations
- messages
- assignment
- notes
- close/reopen

#### Campaigns
- simple template-based campaign
- scheduling
- delivery tracking

#### Audit
- append-only audit logs for important actions

#### Billing
- placeholder usage counters and plan gating
- no payment gateway required yet

---

## Data Model

### tenants
Fields:
- id :binary_id
- name :string
- slug :string
- status :string, default "active"
- plan :string, default "starter"
- vertical :string, default "clinic"
- country :string
- timezone :string
- billing_email :string
- onboarding_status :string, default "not_started"
- owner_user_id :binary_id
- inserted_at / updated_at

Indexes / constraints:
- unique index on slug
- index on owner_user_id

### users
If users already exist, extend carefully.

Required additions:
- tenant_id :binary_id
- role :string, default "owner"
- full_name :string
- status :string, default "active"

Indexes:
- index on tenant_id
- unique constraint strategy appropriate to existing auth model
- if shared email across multiple tenants is allowed, do not force global uniqueness unless existing system requires it

### whatsapp_accounts
Fields:
- id :binary_id
- tenant_id :binary_id
- provider :string
- external_account_id :string
- external_waba_id :string
- external_phone_number_id :string
- display_name :string
- phone_number :string
- quality_rating :string
- status :string, default "pending"
- onboarding_mode :string
- connected_at :utc_datetime
- metadata :map
- inserted_at / updated_at

Indexes:
- index on tenant_id
- unique index on external_account_id where not null
- index on external_waba_id
- index on external_phone_number_id

### onboarding_sessions
Fields:
- id :binary_id
- tenant_id :binary_id
- whatsapp_account_id :binary_id nullable
- provider :string
- external_setup_id :string
- setup_link :text
- state :string, default "created"
- redirect_url :text
- error_code :string
- error_message :text
- expires_at :utc_datetime
- completed_at :utc_datetime
- metadata :map
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on whatsapp_account_id
- unique index on external_setup_id where not null
- index on state

### contacts
Fields:
- id :binary_id
- tenant_id :binary_id
- external_wa_id :string
- phone_e164 :string
- name :string
- first_name :string
- last_name :string
- locale :string
- tags :map
- notes :text
- opt_in_status :string, default "unknown"
- opted_in_at :utc_datetime
- unsubscribed_at :utc_datetime
- last_seen_at :utc_datetime
- metadata :map
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on phone_e164
- unique index on [tenant_id, phone_e164]
- index on external_wa_id

### conversations
Fields:
- id :binary_id
- tenant_id :binary_id
- whatsapp_account_id :binary_id
- contact_id :binary_id
- assigned_user_id :binary_id
- status :string, default "open"
- category :string
- source :string
- unread_count :integer, default 0
- last_message_at :utc_datetime
- closed_at :utc_datetime
- metadata :map
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on whatsapp_account_id
- index on contact_id
- index on assigned_user_id
- index on status
- index on last_message_at

### messages
Fields:
- id :binary_id
- tenant_id :binary_id
- conversation_id :binary_id
- whatsapp_account_id :binary_id
- contact_id :binary_id
- direction :string
- kind :string
- provider_message_id :string
- status :string, default "queued"
- body :text
- payload :map
- sent_at :utc_datetime
- delivered_at :utc_datetime
- read_at :utc_datetime
- failed_at :utc_datetime
- error_code :string
- error_message :text
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on conversation_id
- index on whatsapp_account_id
- index on contact_id
- index on provider_message_id
- index on status
- unique index on provider_message_id where not null if safe

### templates
Fields:
- id :binary_id
- tenant_id :binary_id
- whatsapp_account_id :binary_id
- provider_template_id :string
- name :string
- language :string
- category :string
- status :string
- components :map
- last_synced_at :utc_datetime
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on whatsapp_account_id
- index on status
- unique index on [tenant_id, whatsapp_account_id, name, language]

### campaigns
Fields:
- id :binary_id
- tenant_id :binary_id
- whatsapp_account_id :binary_id
- template_id :binary_id
- created_by_user_id :binary_id
- name :string
- audience_filter :map
- status :string, default "draft"
- scheduled_at :utc_datetime
- started_at :utc_datetime
- completed_at :utc_datetime
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on whatsapp_account_id
- index on template_id
- index on status
- index on scheduled_at

### campaign_deliveries
Fields:
- id :binary_id
- tenant_id :binary_id
- campaign_id :binary_id
- contact_id :binary_id
- message_id :binary_id
- status :string, default "queued"
- error_code :string
- error_message :text
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on campaign_id
- index on contact_id
- index on message_id
- unique index on [campaign_id, contact_id]

### webhook_events
Fields:
- id :binary_id
- tenant_id :binary_id nullable
- provider :string
- provider_event_id :string
- topic :string
- payload :map
- processing_status :string, default "pending"
- processed_at :utc_datetime
- error_message :text
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on provider
- index on topic
- index on processing_status
- index on inserted_at
- unique index on [provider, provider_event_id] where provider_event_id is not null

### audit_logs
Fields:
- id :binary_id
- tenant_id :binary_id
- actor_user_id :binary_id nullable
- action :string
- entity_type :string
- entity_id :binary_id
- payload :map
- inserted_at

Indexes:
- index on tenant_id
- index on actor_user_id
- index on entity_type
- index on entity_id
- index on inserted_at

### usage_counters
Fields:
- id :binary_id
- tenant_id :binary_id
- metric_date :date
- messages_sent :integer, default 0
- messages_received :integer, default 0
- templates_sent :integer, default 0
- active_contacts :integer, default 0
- provider_cost_cents :integer, default 0
- inserted_at / updated_at

Indexes:
- unique index on [tenant_id, metric_date]

### contact_consents
Fields:
- id :binary_id
- tenant_id :binary_id
- contact_id :binary_id
- channel :string, default "whatsapp"
- source :string
- granted_at :utc_datetime
- revoked_at :utc_datetime
- proof :map
- inserted_at / updated_at

Indexes:
- index on tenant_id
- index on contact_id
- index on channel

### Schema Rules
For all schemas:
- add belongs_to / has_many associations
- use `@primary_key {:id, :binary_id, autogenerate: true}`
- use `timestamps(type: :utc_datetime)`
- add changesets with sensible validations
- validate required fields
- add inclusion validations for enums where appropriate
- keep validations MVP-level but solid

---

## Provider Adapter

Create:
- `MyApp.WhatsApp.Provider` behaviour
- `MyApp.WhatsApp.Providers.Kapso` implementation

Callbacks:
- `create_onboarding_session/1`
- `get_onboarding_session/1`
- `send_text_message/1`
- `send_template_message/1`
- `list_templates/1`
- `fetch_account/1`
- `parse_webhook/1`

Rules:
- Keep provider-specific details isolated
- Return normalized internal maps
- Do not spread Kapso-specific payload assumptions throughout business logic
- Add module docs explaining how to later add Meta-direct provider

Kapso implementation should:
- create placeholder HTTP client integration points
- implement request/response normalization
- include TODO markers where real credentials/endpoints are required
- structure code so a real integration can be completed quickly

---

## Onboarding Flow

Build backend flow for:
- tenant owner clicks “Connect WhatsApp”
- backend creates onboarding session through provider adapter
- onboarding session record is stored locally
- setup link is returned to frontend
- callback endpoint receives redirect
- webhook later confirms actual connection state
- local `whatsapp_account` is created or updated
- tenant `onboarding_status` becomes `"connected"` when finished

Required functions:
- `create_session_for_tenant/2`
- `mark_callback_received/2`
- `reconcile_session_from_webhook/1`
- `finalize_connection/2`

Rules:
- webhook truth should be preferred over redirect-only success
- onboarding must be idempotent
- if repeated callbacks/webhooks occur, system remains consistent
- all important transitions should create audit logs

---

## Webhook Ingestion

Create:
- webhook controller
- `ProcessWebhookEventWorker`
- normalization pipeline

Requirements:
- accept raw provider payload
- persist a `webhook_events` record immediately
- respond quickly
- enqueue Oban worker for async processing
- process idempotently
- tolerate duplicates and out-of-order events
- log failures without crashing the request path

Support these event families conceptually:
- account connected / updated
- template updated
- inbound message received
- message status changed (sent/delivered/read/failed)
- onboarding/business-account updates

Inbound message flow:
- identify tenant + whatsapp_account
- upsert contact
- find or create open conversation
- insert inbound message
- update conversation unread_count and last_message_at

Outbound status update flow:
- find message by provider_message_id
- update status timestamps
- update usage counters if appropriate

---

## Inbox + Contacts Core Logic

### Contacts
- `get_contact_by_phone/2`
- `upsert_contact_from_inbound/2`
- `update_opt_in_status/3`

### Inbox
- `get_or_create_open_conversation/3`
- `assign_conversation/3`
- `close_conversation/2`
- `reopen_conversation/2`
- `add_internal_note/3` if modeled separately, otherwise TODO

### Messaging
- create outgoing message record before provider send
- update message status after provider response
- send text reply
- send approved template

Rules:
- maintain tenant isolation
- keep conversation lifecycle simple
- include clear ownership checks
- prevent cross-tenant access

---

## Campaign MVP

Build minimal campaign flow:
- create campaign
- define `audience_filter`
- select template
- schedule time
- enqueue send job
- create campaign_deliveries
- send in chunks through Oban workers

Create:
- Campaigns context
- workers such as `CampaignDispatchWorker` and `CampaignChunkWorker`

Requirements:
- simple audience selection can initially support:
  - all contacts
  - contacts tagged "returning"
  - contacts with `opt_in_status = subscribed`
- chunk sending to avoid giant single jobs
- campaign states should transition correctly
- failures should be recorded per delivery

---

## Clinic / Beauty Starter Templates

Seed or provide helper support for example template records / examples:

- appointment_confirmation
- appointment_reminder_24h
- appointment_reminder_2h
- missed_appointment_followup
- review_request
- recall_checkup_6_months
- promo_teeth_cleaning
- promo_facial_discount

No need to auto-submit templates to provider.
Just model them and make the app ready to sync/send approved templates later.

---

## Routes / Controllers / JSON Contracts

Suggested routes under `/api/v1`:

- `POST   /tenants/:tenant_id/whatsapp/onboarding-sessions`
- `GET    /tenants/:tenant_id/whatsapp/onboarding-sessions/:id`
- `POST   /webhooks/whatsapp/kapso`
- `GET    /whatsapp/onboarding/callback`

- `GET    /tenants/:tenant_id/contacts`
- `GET    /tenants/:tenant_id/conversations`
- `GET    /tenants/:tenant_id/conversations/:id`
- `POST   /tenants/:tenant_id/conversations/:id/assign`
- `POST   /tenants/:tenant_id/conversations/:id/close`
- `POST   /tenants/:tenant_id/conversations/:id/reopen`
- `POST   /tenants/:tenant_id/conversations/:id/messages/text`
- `POST   /tenants/:tenant_id/conversations/:id/messages/template`

- `GET    /tenants/:tenant_id/templates`
- `POST   /tenants/:tenant_id/campaigns`
- `GET    /tenants/:tenant_id/campaigns/:id`

Implement controller actions and JSON responses.
Keep responses consistent and simple:
- success payloads
- validation errors
- not found
- unauthorized / forbidden

---

## Authorization / Security Rules

Enforce:
- tenant owners/admins can manage onboarding and campaigns
- agents can work with conversations and contacts
- viewers are read-only
- every tenant-scoped fetch must verify tenant ownership
- webhook endpoint should validate provider signature if configured; otherwise leave a clear TODO hook
- never trust tenant_id from client without checking current user access

---

## Tests

Add focused tests for:
- changesets
- onboarding session creation
- webhook idempotency
- inbound webhook creates contact/conversation/message
- outbound status webhook updates message
- assignment / close / reopen authorization
- campaign chunk creation
- provider adapter normalization

Use factories/fixtures where appropriate.

---

## Implementation Style

- make small, reviewable changes
- avoid overengineering
- write clear module docs for important boundaries
- prefer service modules where orchestration becomes complex
- use transactions where consistency matters
- use Ecto.Multi for multi-step DB workflows
- add TODO comments only where external provider details are genuinely unknown
- do not invent fake finished integrations; be honest with stubs/placeholders

---

## Execution Order

### Step 1
Show a brief implementation plan mapped to files/modules

### Step 2
Create migrations and schemas

### Step 3
Create provider behaviour + Kapso adapter skeleton

### Step 4
Create onboarding context/services/controllers

### Step 5
Create webhook controller + worker

### Step 6
Create inbox/contacts/campaign core functions

### Step 7
Add routes and tests

### Step 8
Summarize what remains as TODO for real provider credentials, provider payload tuning, and UI integration

When done:
- include all created/updated file paths
- include any migration names
- include any assumptions made
- include manual setup steps required

Do not ask broad questions.
Make reasonable assumptions and proceed.
If project-specific file names differ, adapt cleanly to the existing structure.