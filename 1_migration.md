You are a senior Elixir/Phoenix engineer working inside an existing SaaS codebase.

Implement only the database/domain layer for a multi-tenant WhatsApp-first SaaS for dental clinics, medical clinics, and beauty salons.

Important:
- Do NOT implement controllers
- Do NOT implement routes
- Do NOT implement provider adapters
- Do NOT implement workers
- Do NOT implement webhook handling
- Do NOT implement tests yet
- Focus only on Ecto migrations, schemas, associations, and changesets

Use this file as the project-level source of truth:
- WHATSAPP_CLINIC_SAAS_BLUEPRINT.md

Your task is to implement Step 2 from that blueprint: migrations and schemas.

==================================================
1. GENERAL RULES
==================================================

- Use PostgreSQL
- Use Ecto
- Use binary_id primary keys everywhere for new tables
- Use:
  @primary_key {:id, :binary_id, autogenerate: true}
- Use:
  @foreign_key_type :binary_id
- Use:
  timestamps(type: :utc_datetime)
- Add belongs_to / has_many associations
- Add sensible required validations
- Add inclusion validations for enum-like string fields where appropriate
- Keep validations MVP-level but solid
- Extend existing users schema/migration safely if it already exists
- Do not recreate existing auth tables if they are already in the project
- Prefer additive migrations when adapting existing code

==================================================
2. TABLES TO IMPLEMENT
==================================================

Implement migrations and schemas for:

1. tenants
2. users updates if needed
3. whatsapp_accounts
4. onboarding_sessions
5. contacts
6. conversations
7. messages
8. templates
9. campaigns
10. campaign_deliveries
11. webhook_events
12. audit_logs
13. usage_counters
14. contact_consents

==================================================
3. REQUIRED TABLE DEFINITIONS
==================================================

A. tenants
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

B. users
If users already exist, extend carefully.

Required additions:
- tenant_id :binary_id
- role :string, default "owner"
- full_name :string
- status :string, default "active"

Indexes:
- index on tenant_id
- preserve existing auth strategy
- if email is currently globally unique, keep that unless there is a compelling existing-project reason not to

C. whatsapp_accounts
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

D. onboarding_sessions
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

E. contacts
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

F. conversations
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

G. messages
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

H. templates
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

I. campaigns
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

J. campaign_deliveries
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

K. webhook_events
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

L. audit_logs
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

M. usage_counters
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

N. contact_consents
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

==================================================
4. ASSOCIATIONS TO MODEL
==================================================

Model appropriate associations, including at minimum:

Tenant:
- has_many users
- has_many whatsapp_accounts
- has_many onboarding_sessions
- has_many contacts
- has_many conversations
- has_many messages
- has_many templates
- has_many campaigns
- has_many campaign_deliveries
- has_many webhook_events
- has_many audit_logs
- has_many usage_counters
- has_many contact_consents

User:
- belongs_to tenant
- has_many assigned_conversations, foreign_key: :assigned_user_id
- has_many created_campaigns, foreign_key: :created_by_user_id

WhatsAppAccount:
- belongs_to tenant
- has_many onboarding_sessions
- has_many conversations
- has_many messages
- has_many templates
- has_many campaigns

Contact:
- belongs_to tenant
- has_many conversations
- has_many messages
- has_many campaign_deliveries
- has_many contact_consents

Conversation:
- belongs_to tenant
- belongs_to whatsapp_account
- belongs_to contact
- belongs_to assigned_user
- has_many messages

Message:
- belongs_to tenant
- belongs_to conversation
- belongs_to whatsapp_account
- belongs_to contact

Template:
- belongs_to tenant
- belongs_to whatsapp_account
- has_many campaigns

Campaign:
- belongs_to tenant
- belongs_to whatsapp_account
- belongs_to template
- belongs_to created_by_user
- has_many campaign_deliveries

CampaignDelivery:
- belongs_to tenant
- belongs_to campaign
- belongs_to contact
- belongs_to message

OnboardingSession:
- belongs_to tenant
- belongs_to whatsapp_account

WebhookEvent:
- belongs_to tenant

AuditLog:
- belongs_to tenant
- belongs_to actor_user

UsageCounter:
- belongs_to tenant

ContactConsent:
- belongs_to tenant
- belongs_to contact

==================================================
5. CHANGESET REQUIREMENTS
==================================================

Add sensible changesets for each schema.

At minimum:
- cast relevant fields
- validate required fields
- validate enum-like string fields with validate_inclusion where reasonable
- validate unique constraints matching DB indexes
- validate foreign-key constraints where appropriate

Suggested enum-like values:

Tenant.status:
- active
- suspended
- archived

Tenant.plan:
- starter
- growth
- agency

Tenant.vertical:
- clinic
- dental
- beauty

Tenant.onboarding_status:
- not_started
- in_progress
- connected
- failed

User.role:
- owner
- admin
- agent
- viewer

User.status:
- active
- invited
- disabled

WhatsAppAccount.provider:
- kapso

WhatsAppAccount.status:
- pending
- connected
- disconnected
- failed

Contacts.opt_in_status:
- unknown
- subscribed
- unsubscribed

Conversation.status:
- open
- waiting
- closed

Message.direction:
- inbound
- outbound
- system

Message.kind:
- text
- template
- image
- document
- status

Message.status:
- queued
- sent
- delivered
- read
- failed

Campaign.status:
- draft
- scheduled
- running
- completed
- failed
- cancelled

CampaignDelivery.status:
- queued
- sent
- delivered
- read
- failed
- skipped

WebhookEvent.processing_status:
- pending
- processed
- failed

==================================================
6. IMPLEMENTATION NOTES
==================================================

- If users table already exists, create a safe migration to alter it
- Keep migration names clear and conventional
- Add references with on_delete choices that are reasonable for MVP
- Prefer :nothing or restrictive deletes where data loss would be risky
- Be careful with circular references:
  - tenants.owner_user_id references users
  - users.tenant_id references tenants
  Use a safe migration strategy and document assumptions
- If necessary, create one table first and add a foreign key in a later migration to avoid circular migration problems
- Be explicit and conservative

==================================================
7. OUTPUT FORMAT
==================================================

Do the work in this order:

Step 1:
Show a brief plan of migrations and schema files to create/update

Step 2:
Create migrations

Step 3:
Create/update schemas

Step 4:
Add associations and changesets

Step 5:
Summarize:
- created/updated file paths
- migration names
- assumptions made
- any TODOs related to existing user/auth structure

Do not implement anything outside migrations and schemas.
Make reasonable assumptions and proceed.