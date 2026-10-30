# 0003 — Deploy to Fly.io

**Status:** Accepted
**Date:** 2026-10-29
**Supersedes:** —
**Superseded by:** —

## Context

The app needs a production host. `flyctl` is installed and authenticated locally.
Fly.io has first-class Phoenix support: `fly launch` detects Phoenix, generates a
`Dockerfile` and `fly.toml`, provisions Fly Postgres, and sets `SECRET_KEY_BASE` /
`DATABASE_URL`. Phoenix 1.8 ships release-ready (`mix release`, `rel/overlays/bin/migrate`).

At time of writing the Fly.io account's trial has ended; a payment method must be added
before the first deploy.

## Decision

Deploy jairojobs to Fly.io as an Elixir release in a Docker image, with Fly Postgres
as the database.

## Consequences

**Positive**
- Minimal setup; Phoenix-aware tooling.
- Easy to run close to users (regions) and to scale horizontally later; BEAM clustering
  is supported via DNS discovery if ever needed.
- Release-based deploys with built-in migration hook.

**Negative / trade-offs**
- Vendor-specific `fly.toml`; moving elsewhere means redoing deploy config (Dockerfile is portable).
- Requires a paid account (trial ended).
- Fly Postgres is "unmanaged managed" — backups and upgrades are the app owner's responsibility.

## Alternatives considered

- **Gigalixir** — Elixir-specific PaaS, but smaller ecosystem and pricier at scale.
- **Render / Railway** — generic Docker hosts; workable but no Phoenix-specific tooling.
- **Self-hosted VPS** — maximum control, maximum ops burden; not justified at this stage.
