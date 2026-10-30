# Plan 001: Bootstrap Phoenix Application

**Status:** Decisions confirmed — ready for Phase 2 (generate app)
**Created:** 2026-10-29
**Project dir:** `/Users/jairo/Projects/jairojobs-elixir`

## Goal

Generate a new Elixir Phoenix application in this (currently empty) directory,
verify it runs locally against Postgres, and prepare it for deployment to Fly.io.

## Environment (verified)

| Component          | Version          | Status                              |
|--------------------|------------------|-------------------------------------|
| Elixir             | 1.20.5 (OTP 29)  | ✅ updated from 1.20.4              |
| Phoenix installer  | 1.8.16           | ✅ updated from 1.8.13              |
| Hex / rebar        | present          | ✅                                  |
| PostgreSQL         | 17 (brew)        | ✅ running on :5432, roles `postgres` + `jairo` exist |
| flyctl             | v0.5.1           | ✅ updated from 0.5.0, logged in as raseniero@gmail.com |
| Fly.io account     | —                | ⚠️ trial ended; needs credit card at https://fly.io/trial before deploying |

## Decisions (all confirmed ✅)

| # | Option      | Choices                                                          | Default       |
|---|-------------|------------------------------------------------------------------|---------------|
| 1 | App name    | ✅ **DECIDED: `jairojobs`** → OTP `:jairojobs`, modules `Jairojobs` / `JairojobsWeb`, DB `jairojobs_dev` | `jairojobs`   |
| 2 | App type    | ✅ **DECIDED: Full web app** (HTML + LiveView + Tailwind/daisyUI + Ecto + Swoosh mailer); no extra flags | Full web |
| 3 | Database    | ✅ **DECIDED: PostgreSQL** (local v17 already running; Fly Postgres in prod); no extra flags | Postgres |
| 4 | UI library  | ✅ **DECIDED: Stock Phoenix** (CoreComponents + daisyUI). Petal Components / Petal Pro evaluated and deferred — revisit only if hand-rolled UI becomes a bottleneck | Stock |

## Steps

### Phase 1 — Prep (done)
- [x] Confirm Elixir, Phoenix installer, Postgres, flyctl are installed
- [x] Confirm Postgres is running and accepting connections
- [x] Update Phoenix installer → 1.8.16
- [x] Update Elixir → 1.20.5, flyctl → 0.5.1 (`brew upgrade elixir flyctl`)

### Phase 2 — Generate app
- [x] Confirm decisions in the table above
- [ ] Run generator (final command):
  ```bash
  mix phx.new . --app jairojobs
  ```
- [ ] Fetch deps and install assets when prompted (`Y`)

### Phase 3 — Verify locally
- [ ] `mix ecto.create` — confirm `config/dev.exs` DB credentials work
      (default is `postgres`/`postgres`; switch to `jairo` if auth fails)
- [ ] `mix phx.server` — open http://localhost:4000
- [ ] `mix test` — baseline test suite passes
- [ ] `git init && git add -A && git commit -m "Initial Phoenix app"`

### Phase 4 — Fly.io deployment (later)
- [ ] Add credit card to Fly.io account (trial ended)
- [ ] `fly launch` — auto-detects Phoenix, generates `Dockerfile` + `fly.toml`,
      offers to provision Fly Postgres
- [ ] Set `SECRET_KEY_BASE` / `DATABASE_URL` secrets (fly launch usually handles this)
- [ ] `fly deploy`
- [ ] Verify release migrations run (`bin/migrate` via `rel/overlays`)

## Notes
- Phoenix 1.8 scaffolds with `phx.gen.release`-friendly structure; `fly launch`
  will generate the Dockerfile automatically.
- Directory must stay empty until `mix phx.new .` runs (the generator populates the
  current dir). The `scratchpad/` folder is the only pre-existing content — the
  generator will prompt about existing files; answer accordingly or add
  `scratchpad/` to `.gitignore` if desired.
