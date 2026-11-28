# 0007 — Fly Managed Postgres instead of self-run Fly Postgres

**Status:** Accepted
**Date:** 2026-11-27
**Supersedes:** ADR-0003, in part (its choice of database host; the rest stands)
**Superseded by:** —

## Context

ADR-0003 chose Fly.io for hosting with "Fly Postgres" as the database. It noted Fly Postgres
is "unmanaged managed": backups, failover and upgrades are the app owner's job. Since then
Fly.io points new apps to **Fly Managed Postgres (MPG)**, which Fly runs for you. Its
Developer plan costs $4 a month and gives two 256 MB members with failover, up to 5 GB of
storage and a daily backup kept for ten days. The `citext` extension that spec 001's
migration creates is on its list of trusted extensions.

The first deploy was set up on 2026-11-27, and the owner chose MPG for it.

## Decision

- Production uses Fly Managed Postgres, **Developer plan**, Postgres **17** (the same as CI,
  ADR-0002). The cluster is `jairojobs-db` (id `kzpwm0j93epr4nv3`) in `sin`, org `jairosoft`.
- `fly mpg attach` sets the app's `DATABASE_URL` secret. On the Developer plan the app
  connects to Postgres directly over Fly's private network, without a pooler (PgBouncer comes
  with Basic and up), so the Repo needs no pooler settings (`prepare: :unnamed`, a separate
  direct URL for migrations).
- The cluster **pauses after 15 minutes with no client** and takes 15-25 s to wake on the
  next connection. The prod Repo in `config/runtime.exs` therefore waits up to 30 s to
  connect and for a connection (`connect_timeout`, `handshake_timeout`, `queue_target`,
  `queue_interval`), and its pool defaults to 5, since the plan allows 20 connections in
  all. Without this the first deploy's migration failed with "connection not available".
- The rest of ADR-0003 is unchanged: an Elixir release in a Docker image on Fly Machines.

## Consequences

**Positive**
- Backups, failover and minor upgrades are Fly's job, not the owner's.
- It is cheap at launch and can move up a plan without changing the code.

**Negative / trade-offs**
- Auto-pause: the first request after 15 quiet minutes waits for the cluster to wake, about
  15-25 s. With the app's own machines stopping when idle (`fly.toml`), a quiet site's first
  visitor waits for both.
- 256 MB members and no point-in-time restore on the Developer plan: a bad migration can
  only be undone to the last daily backup. Move to Basic before the data matters that much.
- The database is reachable only inside the Fly organisation's private network; from a
  laptop it is `fly mpg connect` or `fly mpg proxy`.
- Ties the database to Fly.io a little more than self-run Postgres did; a `pg_dump` still
  moves it anywhere.

## Alternatives considered

- **Self-run Fly Postgres (ADR-0003 as written)** — the owner keeps backups and failover;
  more work for no saving at this size.
- **An outside managed Postgres (Neon, Supabase, Crunchy)** — traffic leaves Fly's private
  network, and there is one more vendor.
