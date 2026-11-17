# Data Model

**Last updated:** 2026-11-16 (moderation columns and checks on `listings`, spec 004)

Living document. Update the ERD and table list when a spec adds or changes schemas.
The authoritative source is `priv/repo/migrations/` + the `Ecto.Schema` modules;
this page is the readable summary.

## Conventions

- Primary keys: UUID v7 (`:binary_id`), app-generated; all FKs `:binary_id` (ADR-0004)
- Public listing URLs use a unique slug only; the UUID stays the primary key and appears only in private addresses (constitution §4.8, ADR-0004)
- Regions: unique slug set once at creation; hidden via `active = false`, never deleted
- Timestamps: `inserted_at` / `updated_at` (`utc_datetime_usec`)
- Soft deletes: not used unless a spec requires it
- Money: integer centavos in the database, whole pesos in code via `Jairojobs.Pesos` (constitution §4.5)
- Naming: snake_case, plural table names, singular schema modules

## ERD

![ERD](diagrams/out/erd-jairojobs.svg)

*Source: `diagrams/src/erd-jairojobs.puml`. Status: matches the migrations through spec 004's two (moderation columns, moderation checks).*

## Tables

| Table | Schema module | Context | Introduced by spec | Status |
|---|---|---|---|---|
| `users` | `Jairojobs.Accounts.User` | Accounts | 001 | Implemented |
| `users_tokens` | `Jairojobs.Accounts.UserToken` | Accounts | 001 | Implemented |
| `regions` | `Jairojobs.Regions.Region` | Regions | 002 | Implemented |
| `listings` | `Jairojobs.Listings.Listing` | Listings | 003, 004 | Implemented (employer side 003, moderation 004; public slug in 005) |

Spec 003 also added `business_name` and `business_about` to `users`.

Spec 004 added four columns to `listings` for the latest Admin decision: `published_at`
(set once, on approval; the "posted" date for spec 005), `decided_at`, `decided_by_id` and
`takedown_reason`. What the decision was is not stored; it follows from the status.

Planned, not yet designed: `profiles` + CV files (006),
`applications` (007), `subscriptions` (011).
