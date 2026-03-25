# AGENTS.md

## Project Overview

This project is a **multi-tenant WhatsApp-first SaaS** for **dental clinics, medical clinics, and beauty salons**.

Primary product goals:
- onboard tenant businesses to WhatsApp through a provider-backed flow
- manage inbound and outbound customer conversations
- send approved template messages
- support appointment reminders, confirmations, follow-ups, and simple campaigns

This is **not** a generic omnichannel CRM.
This is a focused, MVP-first product centered on WhatsApp communications for clinics and salons.

---

## Product Scope

### In scope
- multi-tenant SaaS architecture
- tenant onboarding
- WhatsApp account onboarding flow
- contacts
- inbox / conversations / messages
- approved templates
- simple campaigns
- audit logs
- usage counters
- role-based access

### Out of scope for MVP unless explicitly requested
- full CRM pipelines
- multi-channel messaging
- payment gateway integration
- complex AI agents
- advanced analytics warehouse
- mobile apps
- direct Meta production integration without placeholders/stubs
- broad generic abstractions not needed for current milestone

---

## Core Domain Model

Main contexts:
- Accounts
- Tenants
- WhatsApp
- Onboarding
- Contacts
- Inbox
- Campaigns
- Audit
- Billing

Main entities:
- tenants
- users
- whatsapp_accounts
- onboarding_sessions
- contacts
- conversations
- messages
- templates
- campaigns
- campaign_deliveries
- webhook_events
- audit_logs
- usage_counters
- contact_consents

Use the project blueprint file as product source of truth:
- `WHATSAPP_CLINIC_SAAS_BLUEPRINT.md`

If implementation details are unclear, prefer alignment with that blueprint.

---

## Tech Stack Expectations

- Elixir
- Phoenix
- Ecto
- PostgreSQL
- Oban

General assumptions:
- backend-first implementation
- JSON APIs are acceptable
- one VPS deployment is acceptable for MVP
- Redis is not required unless explicitly requested
- provider adapter architecture must allow starting with Kapso and later supporting Meta-direct

---

## Architecture Rules

### Multi-tenancy
- Use shared-schema multi-tenancy
- All tenant-owned records must include `tenant_id`
- Never perform tenant-scoped reads or writes without explicit tenant checks
- Never trust `tenant_id` from external input without authorization checks

### Data durability
- All durable business state must be stored in PostgreSQL
- Oban is the async job system of record
- Avoid introducing Redis unless there is a strong, explicit reason

### Provider integration
- Isolate provider-specific logic behind a behaviour
- Do not leak Kapso-specific payload structures into core business logic
- Normalize provider data before it reaches domain code

### Webhooks
- Webhooks must be idempotent
- Persist raw webhook events before processing
- Prefer async processing via Oban
- Webhook-confirmed state is more trustworthy than redirect-only success in onboarding flows

---

## Coding Principles

### General
- make small, reviewable changes
- preserve existing project structure where possible
- prefer explicit code over clever code
- do not overengineer
- avoid speculative abstractions
- keep functions focused and readable
- add module docs for important boundaries and context responsibilities

### Phoenix / Elixir
- use contexts properly
- put orchestration in service modules or context functions when needed
- use `Ecto.Multi` for multi-step DB workflows that must stay consistent
- prefer pattern matching and explicit return values
- avoid deeply nested conditionals when a clearer control flow is possible

### Ecto
- use `:binary_id` for new primary and foreign keys
- use `timestamps(type: :utc_datetime)`
- include sensible changeset validations
- back every important uniqueness rule with a DB constraint/index
- model associations clearly and consistently
- be conservative with `on_delete`; avoid accidental data loss

### Migrations
- prefer additive, safe migrations
- do not rewrite existing auth tables unless necessary
- if users already exist, alter safely
- handle circular references carefully
- name migrations clearly and conventionally

### Controllers / APIs
- keep JSON responses consistent
- return clear validation errors
- do not place business logic directly in controllers
- authorize every tenant-scoped action

### Background jobs
- jobs must be idempotent where practical
- keep job payloads small and explicit
- log failure context clearly
- do not hide side effects

---

## Domain-Specific Product Guidance

This product is optimized for:
- dental clinics
- medical clinics
- beauty salons

Typical workflows:
- appointment confirmation
- reminder 24h before visit
- reminder 2h before visit
- reschedule flow
- no-show follow-up
- post-visit follow-up
- review request
- recall campaign
- promotional campaigns
- inbound customer questions

When making product decisions, prioritize these workflows over generic business use cases.

---

## Authorization Rules

Roles:
- owner
- admin
- agent
- viewer

Expected permissions:
- owner/admin: onboarding, campaigns, settings, management
- agent: conversations, contacts, messaging work
- viewer: read-only

Agent instructions:
- enforce authorization at boundaries
- never assume route-level protection is enough
- every tenant-scoped fetch must verify current user access

---

## File / Module Conventions

Prefer clean boundaries such as:

- `lib/<app>/accounts/`
- `lib/<app>/tenants/`
- `lib/<app>/whatsapp/`
- `lib/<app>/onboarding/`
- `lib/<app>/contacts/`
- `lib/<app>/inbox/`
- `lib/<app>/campaigns/`
- `lib/<app>/audit/`
- `lib/<app>/billing/`

Possible provider adapter layout:
- `lib/<app>/whatsapp/provider.ex`
- `lib/<app>/whatsapp/providers/kapso.ex`

Possible worker layout:
- `lib/<app>/workers/process_webhook_event_worker.ex`
- `lib/<app>/workers/campaign_dispatch_worker.ex`
- `lib/<app>/workers/campaign_chunk_worker.ex`

Follow existing app naming conventions if they differ.

---

## What to Do Before Making Changes

Before implementing:
1. inspect existing contexts, schemas, migrations, and auth model
2. check whether `users` already exists and how authentication is implemented
3. check naming conventions already used in the codebase
4. check whether `binary_id` is already the project standard
5. check whether Oban is already installed/configured
6. read `WHATSAPP_CLINIC_SAAS_BLUEPRINT.md`

If the existing project structure conflicts with this file, adapt carefully rather than duplicating concepts blindly.

---

## What to Avoid

- do not build features outside the current task
- do not add Redis unless explicitly requested
- do not add unnecessary generic platform abstractions
- do not create fake “finished” external integrations
- do not silently invent provider payload formats without marking assumptions
- do not bypass tenant isolation for convenience
- do not put complex business logic in controllers
- do not make destructive schema changes without necessity
- do not change unrelated files opportunistically

---

## External Integration Guidance

### Kapso
- Kapso is the initial provider target
- integrate through a provider adapter
- keep credentials, endpoints, and payload specifics configurable
- where exact payload formats are unknown, use clear TODOs and normalized interfaces

### Meta direct support
- do not design the app so Kapso is hardcoded forever
- keep interfaces extendable for a future Meta-direct provider

---

## Testing Expectations

When adding or changing code, prefer focused tests for:
- changesets
- authorization boundaries
- tenant isolation
- webhook idempotency
- onboarding state transitions
- inbound message processing
- outbound message status updates
- campaign chunking logic
- provider adapter normalization

Do not add broad, flaky tests when focused domain tests are sufficient.

---

## Preferred Working Style for Agents

When given a task:
1. identify the exact scope
2. inspect existing code before generating new code
3. make the smallest coherent set of changes
4. explain assumptions clearly
5. list created/updated files
6. note TODOs honestly, especially for external integrations

If a task is too broad, break it into smaller steps internally and implement the requested slice cleanly.

---

## Decision Heuristics

When multiple implementations are possible, prefer:
1. consistency with existing codebase
2. tenant safety
3. idempotency
4. explicitness
5. simpler MVP-friendly design
6. future extensibility without overengineering

---

## Task-Specific Reminder

Current blueprint file:
- `WHATSAPP_CLINIC_SAAS_BLUEPRINT.md`

Current likely implementation order:
1. migrations + schemas
2. contexts + core domain logic
3. provider adapter
4. onboarding flow
5. webhook ingestion
6. campaigns/workers
7. controllers/routes
8. tests and refinement

Unless explicitly requested otherwise, stay aligned with that order.