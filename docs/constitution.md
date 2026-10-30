# Constitution

**Status:** Draft
**Last updated:** 2026-10-29

Non-negotiable principles for jairojobs. Every spec, plan, and PR is measured against this file.
Change it deliberately, via an ADR.

## 1. Stack

| Layer | Choice | Notes |
|---|---|---|
| Language / runtime | Elixir 1.20 / OTP 29 | |
| Web | Phoenix 1.8, LiveView | Server-rendered first; LiveView for interactivity |
| UI | Stock `CoreComponents` + Tailwind v4 + daisyUI | No third-party component library (ADR-0001) |
| Database | PostgreSQL 17 via Ecto | (ADR-0002) |
| Deployment | Fly.io | (ADR-0003) |
| Background jobs | _TBD_ | |
| Email | Swoosh | Local dev mailbox at `/dev/mailbox` |

## 2. Principles

<!-- Fill in with the user. Suggested starting points: -->

- _Simple over clever_ — …
- _Boring technology_ — …
- _Server-rendered by default_ — …
- _Tests are part of the feature_ — …

## 3. Testing rules

- …

## 4. Code conventions

- Follow `AGENTS.md` (Phoenix-generated) for Elixir/Phoenix/LiveView idioms.
- …

## 5. What we deliberately do NOT do

- …

## 6. How specs are written

- Specs describe **what** and **why**; never **how**.
- User stories in the form: _As a \<persona\>, I want \<goal\>, so that \<benefit\>._
- Every requirement has an ID (`REQ-NNN-n`) and Given/When/Then acceptance criteria.
- "Out of scope" and "Open questions" sections are mandatory, even if empty.
- A spec must be `Approved` before a plan is written.

## 7. Definition of Done

- …
