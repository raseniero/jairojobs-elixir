# 001 — Accounts & Authentication — Tasks

**Status:** Approved (2026-10-31)
**Plan:** [plan.md](./plan.md) (Approved 2026-10-30)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-001-n: <scenario>`.
Scenario-first (constitution §3.12): write the tests listed under a task first, see them fail,
then implement. T4 (generated), T10b and T11 (markup) are the allowed exceptions.

## Phase A — Prerequisites (no auth code yet)

- [x] **T1** — CI workflow (constitution §3.9–10) — done 2026-11-02, run 41370888866 green
  - `.github/workflows/ci.yml`: Elixir 1.20 / OTP 29, Postgres 17 service, deps cache,
    `mix precommit`; `paths-ignore: [docs/**, scratchpad/**, "**/*.md"]`
  - Commit: `ci: run mix precommit on push and PR`
  - Verify: push a branch, see green check

- [x] **T2** — UUID v7 + usec timestamps foundation (ADR-0004; plan decisions 5, 8) — done 2026-11-02
  - `config/config.exs`: `:generators` → `binary_id: true, timestamp_type: :utc_datetime_usec`;
    `Jairojobs.Repo` → `migration_primary_key`, `migration_foreign_key`, `migration_timestamps`
  - `lib/jairojobs/schema.ex`: `Jairojobs.Schema` macro (`Ecto.UUID` v7 PK, `Ecto.UUID` FK type,
    usec timestamps)
  - Test: `test/jairojobs/schema_test.exs` — a throwaway schema using the macro autogenerates
    a version-7 UUID (check the version nibble)
  - Commit: `feat: UUID v7 schema foundation (ADR-0004)`

- [x] **T3** — Configurable mailer sender (ADR-0005) — done 2026-11-02
  - `config/config.exs`: `config :jairojobs, :mailer_from, {"jairojobs", "hello@jairojobs.com"}`
  - `config/runtime.exs` prod block: `Swoosh.Adapters.Resend` + `RESEND_API_KEY`
  - Commit: `feat: configurable mailer sender; Resend adapter in prod (ADR-0005)`

## Phase B — Generate and adapt auth

- [x] **T4** — Run `mix phx.gen.auth Accounts User users --live` (REQ-001-1…8) — done 2026-11-04
  - Run generator; `mix deps.get`; **do not** run the migration yet
  - Edit migration: timestamps → `:utc_datetime_usec`; keep citext, indexes
  - Switch `User` and `UserToken` to `use Jairojobs.Schema`
  - `UserNotifier`: `from` reads `:mailer_from`; login email body states the 15-minute expiry
  - `mix ecto.migrate`; `mix test` — all generated tests green
  - Commit: `feat(accounts): phx.gen.auth baseline (REQ-001-1..8)`

- [x] **T5** — Rename generated tests to the `REQ-001-n: <scenario>` convention (plan decision 10) — done 2026-11-04
  - Map each generated test to its scenario in `spec.md`; rename only, no behaviour change
  - Add any scenario the generator doesn't cover (e.g. "Protected page redirects and returns",
    "Expired or used link") as new tests
  - Commit: `test(accounts): align generated tests with REQ-001 scenarios`

- [x] **T5b** — Neutral sign-up response for existing emails (REQ-001-2 "Existing email is not revealed") — done 2026-11-04
  - `UserLive.Registration`: when `register_user/1` fails **only** on the email uniqueness
    constraint, behave exactly like a successful sign-up — redirect to `/users/log-in` with the
    same "An email was sent to …" flash; do not surface "has already been taken". Other
    validation errors (format, length, missing role) still render inline
  - Do **not** email the existing account (no unsolicited login link); no new account is created
  - Tests (`registration_test.exs`): rewrite `REQ-001-2: existing email does not create a duplicate
    account` to assert the neutral redirect + flash, no second user, and no email delivered
    (`refute_email_sent` via `Swoosh.TestAssertions`); keep the context-level uniqueness test
  - Commit: `feat(accounts): neutral sign-up response for existing emails (REQ-001-2)`

- [x] **T5c** — Password login requires a confirmed email (REQ-001-5 "Password login requires confirmed email") — done 2026-11-04
  - `Accounts.get_user_by_email_and_password/2`: return `nil` unless `user.confirmed_at` is set
    (still run `Bcrypt.no_user_verify/0` path for timing parity)
  - Tests: context `REQ-001-5: unconfirmed user cannot log in with a password`; controller
    `REQ-001-5: password login is refused for an unconfirmed email` (generic
    "Invalid email or password" flash, no session)
  - Commit: `feat(accounts): password login requires confirmed email (REQ-001-5)`

- [x] **T6** — Role column and sign-up selection (REQ-001-2, REQ-001-9) — done 2026-11-04
  - Migration `add_role_to_users`: `role :string, null: false` + CHECK constraint,
    `previous_role :string`, `create index(:users, [:role])`
  - `User`: `field :role, Ecto.Enum, values: [:candidate, :employer, :admin]`,
    `field :previous_role, Ecto.Enum, ...`; `registration_changeset/3` casts `role`,
    `validate_required`, `validate_inclusion(:role, [:candidate, :employer])`
  - `UserLive.Registration`: radio group "I'm looking for work" / "I'm hiring"; no admin option
  - `Scope`: `role/1`, `admin?/1`
  - Tests: `REQ-001-2: successful sign-up` (role persisted), `REQ-001-2: missing role`,
    `REQ-001-2: forged admin role is rejected`, `REQ-001-9: role available in scope`
  - Commit: `feat(accounts): user role chosen at sign-up (REQ-001-2, REQ-001-9)`

- [x] **T7** — Read-only role label in Settings (REQ-001-9) — done 2026-11-04
  - `UserLive.Settings`: show "Account type: Candidate / Employer / Admin"; `role` never cast
  - Tests: `REQ-001-9: role shown in Settings`, `REQ-001-9: users cannot change their own role`
    (submitting `role` param is ignored)
  - Commit: `feat(accounts): show account type in settings (REQ-001-9)`

## Phase C — Admin promotion

- [ ] **T8** — Promote / demote context functions (REQ-001-11)
  - `Accounts.promote_to_admin(scope, user)`, `Accounts.demote_admin(scope, user)`,
    `Accounts.count_admins/0`; `Scope.system/0`
  - Rules: non-admin scope → `{:error, :unauthorized}`; unconfirmed → `{:error, :unconfirmed}`;
    already admin → `{:ok, user}` no-op; last admin → `{:error, :last_admin}`;
    demote restores `previous_role` or `:candidate`; demote runs in a transaction with
    `FOR UPDATE` on the target row
  - Tests (context): all four REQ-001-11 scenarios + `REQ-001-10: unconfirmed user cannot be promoted`
  - Commit: `feat(accounts): promote/demote admin rules (REQ-001-11)`

- [ ] **T9** — Mix task `jairojobs.admin` (REQ-001-10)
  - `lib/mix/tasks/jairojobs.admin.ex`: `promote EMAIL` | `demote EMAIL`; starts the app,
    calls T8 with `Scope.system()`; prints one line; non-zero exit on error
  - Tests: `test/mix/tasks/jairojobs.admin_test.exs` — promote, demote, unknown email,
    unconfirmed user, last admin (assert output + `Mix.raise`)
  - Document usage in project `README.md`
  - `Jairojobs.Release.promote_admin/1` / `demote_admin/1` (production entry points) are
    **deferred** to the Fly.io deployment task, when `phx.gen.release` creates the module.
    Until then the mix task is the only entry point.
  - Commit: `feat(accounts): mix jairojobs.admin promote|demote (REQ-001-10)`

- [ ] **T10** — `require_admin` hook/plug (plan decision 7)
  - `UserAuth`: `on_mount(:require_admin, …)` and `require_admin/2` plug → 403 or redirect
    with flash for non-admins; `live_session :require_admin` scaffold in router (no routes yet)
  - Tests: `test/jairojobs_web/user_auth_test.exs` — admin passes, candidate/employer refused,
    visitor redirected
  - Commit: `feat(web): require_admin auth hook (prep for spec 004)`

## Phase D — Design foundation and navigation

- [ ] **T10b** — Apply the design guide theme (`docs/design.md` §3)
  - `assets/css/app.css`: replace generated `light` + `dark` theme blocks with the single
    `jairojobs` theme; remove the theme toggle from `layouts.ex` / `root.html.heex`
  - `core_components.ex`: adjust button/input defaults only where they conflict with the
    tokens (radius, sizes); keep the component API unchanged
  - Wordmark component per design.md §4
  - No tests beyond compile + existing suite (markup task); check at 375 px in the browser
  - Commit: `feat(ui): jairojobs daisyUI theme and wordmark (design.md)`


- [ ] **T11** — Role-aware navigation (REQ-001-12, REQ-001-1)
  - `Layouts`: header + drawer per `wireframe-nav`; items per role; placeholders for 003/006/007
    link to `#` with a `data-placeholder` attribute; mobile-first, checked at 375 px
  - Tests: `test/jairojobs_web/components/layouts_test.exs` (4 role variants by DOM id) and
    one LiveView smoke test per role rendering `/`
  - Commit: `feat(web): role-aware navigation (REQ-001-12)`

## Phase E — Close

- [ ] **T12** — Docs and DoD
  - `docs/architecture/data-model.md`: tables → *Implemented*; ERD unchanged unless columns differ
  - `docs/architecture/overview.md`: Accounts context → *Implemented*
  - `README.md`: admin command, dev mailbox URL
  - `spec.md` + `plan.md` status → `Done`; feature map in spec 000 → Done
  - Walk the Definition of Done checklist (constitution §7); note "Deployed to Fly.io" as
    deferred until Phase 4 of the bootstrap plan
  - Commit: `docs(spec 001): mark done`

## Notes / deviations from plan

<!-- Record anything that changed during implementation and why. -->

- T5: two spec scenarios differ from generator behaviour and were **not** changed (rename-only task).
  Decision 2026-11-04: keep the spec, fix the code — added **T5b** (neutral sign-up response,
  REQ-001-2) and **T5c** (confirmed-email guard on password login, REQ-001-5).
  - REQ-001-2 "Existing email is not revealed" — the generated sign-up form shows
    "has already been taken" (enumeration).
  - REQ-001-5 "Password login requires confirmed email" — `get_user_by_email_and_password/2`
    does not check `confirmed_at`. The state is unreachable through the UI today (a password can
    only be set in Settings, which requires a confirmed login), but the guard is defence in depth.
  Added tests beyond the generator: `REQ-001-1` public home page, protected-page round trip,
  `REQ-001-3` expired link, `REQ-001-4` used link.
- T4: the migration already came out with `:utc_datetime_usec` timestamps and `:binary_id` keys
  thanks to the T2 generator config — no manual migration edits were needed. The generator also
  appended an "Authentication" section to `AGENTS.md` (kept).
- T1: first run failed — `mix deps.get --only test` omitted dev-only deps, so `deps.unlock --unused`
  pruned `mix.lock` and the no-diff check failed. Fixed by fetching all deps.
