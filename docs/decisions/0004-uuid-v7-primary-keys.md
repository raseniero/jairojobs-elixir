# 0004 — UUID v7 primary keys for all tables

**Status:** Accepted
**Date:** 2026-10-29
**Supersedes:** —
**Superseded by:** —

## Context

Phoenix defaults to `bigint` auto-increment primary keys. These produce short, readable URLs
but are enumerable: anyone can guess adjacent IDs and infer counts of listings, users, and
applications. jairojobs holds private records (applications, CVs, profiles) where an
authorization slip combined with guessable IDs is a real exposure, and public counts are a
business metric we'd rather not leak.

Random UUID v4 avoids this but fragments B-tree indexes. UUID **v7** is time-ordered, keeps
insert locality close to bigint, and is natively supported by Elixir 1.20 / Ecto
(`Ecto.UUID` + `UUIDv7` generation).

The choice must be made before the first migration (`phx.gen.auth`), as changing later means
rewriting migrations and foreign keys.

## Decision

- All tables use UUID v7 primary keys (`:binary_id`), generated application-side.
- All foreign keys are `:binary_id`.
- Configure once in `config/config.exs` so generators and migrations default to it:
  `migration_primary_key: [type: :binary_id]`, `migration_foreign_key: [type: :binary_id]`,
  and `generators: [binary_id: true]`.
- Public-facing listing URLs use a **slug** in addition to the UUID
  (e.g. `/jobs/davao-city/barista-cafe-x`) so URLs stay human-friendly.

## Consequences

**Positive**
- Unguessable IDs: defense in depth for private resources; no leakage of growth metrics.
- IDs can be generated before insert (useful for uploads and async flows).
- Globally unique; safe for future data merges/exports.
- v7 ordering keeps index performance close to bigint.

**Negative / trade-offs**
- 16-byte keys vs 8; marginally larger indexes.
- Harder to read/type in logs and support conversations.
- Slugs add a small amount of work (generation, uniqueness, redirects on rename).

## Alternatives considered

- **bigint** — simplest, Phoenix default; rejected for enumerability and metric leakage.
- **UUID v4** — unguessable but random; index fragmentation with no upside over v7.
- **bigint internally + public opaque ID (hashids/NanoID)** — works, but two ID systems to
  maintain; UUID v7 achieves the same with one.
