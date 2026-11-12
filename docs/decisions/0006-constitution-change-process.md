# 0006 — How the constitution changes: ADRs for stack and principles, direct edits for process rules

**Status:** Accepted
**Date:** 2026-11-12
**Supersedes:** —
**Superseded by:** —

## Context

`docs/constitution.md` said of itself: "Change it deliberately, via an ADR." In practice
only stack choices got ADRs (0001–0005: UI library, database, hosting, primary keys, email).
Three process rules were added to the constitution directly, without an ADR, during the
first days of the project: Gherkin acceptance scenarios (2026-10-30), scenario-first testing
in §3.12 and the diagram rules in §6 (both 2026-10-31).

The mismatch surfaced on 2026-11-12, when a small process improvement (reconciling diagrams
before a spec closes) was kept out of the Definition of Done only because adding it would
have required an ADR. A rule that makes small process fixes expensive tends to be skipped
or worked around, and a rule that is not followed is worse than no rule.

The two kinds of rule differ in what a change costs. Stack and architecture choices are
expensive to reverse and their reasoning is easy to forget. Process rules are cheap to
adjust and are expected to be tuned as the project learns.

## Decision

- **§1 Stack, §2 Principles and §5 What we deliberately do NOT do** change only through an
  ADR. These are the rules that are costly to reverse or that define what the project is.
- **§3 Testing rules, §4 Code conventions, §6 How specs are written and §7 Definition of
  Done** may be edited directly. Each such edit is recorded in the constitution's
  "Last updated" line with the date and a few words on what changed.
- A code convention that fixes an architecture choice (for example the money type or the
  shape of public addresses) is treated as a stack rule and gets an ADR.
- The three process rules added without an ADR in October 2026 stand as they are.

## Consequences

**Positive**
- The stated rule matches what is actually done.
- ADRs stay reserved for decisions worth a dated record of context and alternatives.
- Process improvements found during a spec can be adopted in the same commit.

**Negative / trade-offs**
- Process rules have no record of the alternatives considered; the commit message and the
  "Last updated" note are the only trail.
- The line between a convention and an architecture choice needs judgement.

## Alternatives considered

- **Keep "via an ADR" for every section and follow it strictly** — rejected; an ADR per
  process tweak is more ceremony than a one-person project will sustain.
- **Leave the header as it was** — rejected; the rule and the practice would keep disagreeing.
- **Drop ADRs for the constitution entirely** — rejected; stack decisions are exactly where
  the reasoning is worth keeping.
