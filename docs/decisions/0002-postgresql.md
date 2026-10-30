# 0002 — PostgreSQL as the primary database

**Status:** Accepted
**Date:** 2026-10-29
**Supersedes:** —
**Superseded by:** —

## Context

Phoenix supports PostgreSQL, MySQL, MSSQL, and SQLite via Ecto. PostgreSQL 17 is already
installed and running locally (Homebrew). The deployment target (Fly.io, ADR-0003) offers
managed Postgres.

## Decision

Use PostgreSQL (17 locally; Fly Postgres in production) via `ecto_sql` + `postgrex`.
Generated with `mix phx.new` defaults — no `--database` flag.

## Consequences

**Positive**
- Full Ecto feature set: `jsonb`, full-text search, array columns, advisory locks, etc.
- Mature tooling and the default choice across the Phoenix ecosystem.
- Matches production target; no dev/prod database divergence.

**Negative / trade-offs**
- Requires a running Postgres for dev and test (already satisfied locally; CI will need a service).
- Slightly more operational overhead than SQLite for a single-instance app.

## Alternatives considered

- **SQLite** — zero-setup, but on Fly.io requires a persistent volume and single-instance
  deploys; weaker fit for a multi-user job board.
- **MySQL** — not installed locally; no advantage over Postgres here.
