# 0001 — Stock Phoenix UI (CoreComponents + daisyUI) over Petal Components / Petal Pro

**Status:** Accepted
**Date:** 2026-10-29
**Supersedes:** —
**Superseded by:** —

## Context

Phoenix 1.8 generates `CoreComponents` (~10 HEEx components) with Tailwind v4 and daisyUI,
and its generators (`phx.gen.live`, `phx.gen.auth`, …) emit markup for those components.

Petal offers a free MIT library (`petal_components`, ~200 shadcn-style components, with an
MCP server and usage rules for AI agents) and a paid SaaS boilerplate (Petal Pro).
Development will be done primarily with Claude Code.

## Decision

Start with stock Phoenix: `CoreComponents` + Tailwind + daisyUI. Do not add Petal
Components or Petal Pro at this stage.

## Consequences

**Positive**
- Generators, `phx.gen.auth`, tutorials, and agent training data all line up with the code.
- Components live in the repo and are fully editable.
- No dependency on a third-party release cadence; fewer breaking-upgrade risks.
- Adding Petal later is easy; removing it later would be tedious.

**Negative / trade-offs**
- Richer UI (dropdowns, tabs, data tables, modals-with-forms) must be hand-built on daisyUI.
- Risk of UI inconsistency across many agent sessions; mitigated by documenting design
  conventions in `docs/constitution.md` and `AGENTS.md`.

## Alternatives considered

- **Petal Components (free)** — faster UI and good agent tooling (MCP, usage rules), but clashes
  with `CoreComponents` names and requires patching generator output on every feature.
- **Petal Pro (paid)** — full SaaS boilerplate (tenancy, billing, admin); replaces `mix phx.new`
  entirely. Overkill for current scope; revisit if SaaS plumbing becomes a priority.

Revisit trigger: hand-rolled UI becomes a measurable bottleneck.
