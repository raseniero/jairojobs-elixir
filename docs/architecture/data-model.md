# Data Model

**Last updated:** 2026-11-10 (regions implemented by spec 002)

Living document. Update the ERD and table list when a spec adds or changes schemas.
The authoritative source is `priv/repo/migrations/` + the `Ecto.Schema` modules;
this page is the readable summary.

## Conventions

- Primary keys: UUID v7 (`:binary_id`), app-generated; all FKs `:binary_id` (ADR-0004)
- Public listing URLs: UUID + unique slug
- Regions: unique slug set once at creation; hidden via `active = false`, never deleted
- Timestamps: `inserted_at` / `updated_at` (`utc_datetime_usec`)
- Soft deletes: not used unless a spec requires it
- Naming: snake_case, plural table names, singular schema modules

## ERD

![ERD](diagrams/out/erd-jairojobs.svg)

*Source: `diagrams/src/erd-jairojobs.puml`. Status: matches the migrations through spec 002.*

## Tables

| Table | Schema module | Context | Introduced by spec | Status |
|---|---|---|---|---|
| `users` | `Jairojobs.Accounts.User` | Accounts | 001 | Implemented |
| `users_tokens` | `Jairojobs.Accounts.UserToken` | Accounts | 001 | Implemented |
| `regions` | `Jairojobs.Regions.Region` | Regions | 002 | Implemented |

Planned, not yet designed: `listings` (003), `profiles` + CV files (006),
`applications` (007), `subscriptions` (011).
