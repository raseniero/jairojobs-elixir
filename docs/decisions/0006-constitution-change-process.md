# 0006 — How the constitution changes: ADRs for stack, principles and any loosening; direct edits only to tighten process rules

**Status:** Accepted
**Date:** 2026-11-12 (amended 2026-11-13, before it was first pushed)
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
  Done** may be edited directly **only to add a rule or make one stricter**. Removing or
  relaxing a rule in these sections needs an ADR, like the sections above. Clarifying the
  wording or fixing an example without changing what the rule requires is a direct edit.
- **Every edit to the constitution needs the owner's explicit approval** and goes in its own
  commit, never together with feature work that the change would make easier to pass.
- **Every edit is recorded in a Changelog table at the end of the constitution** (date and
  what changed), in place of a single "Last updated" note.
- A code convention that fixes an architecture choice (for example the money type or the
  shape of public addresses) is treated as a stack rule and gets an ADR.
- The three process rules added without an ADR in October 2026 stand as they are.

## Consequences

**Positive**
- The stated rule matches what is actually done.
- ADRs stay reserved for decisions worth a dated record of context and alternatives.
- Process improvements found during a spec can be adopted in the same commit.

- The quality bar cannot be lowered quietly: loosening always leaves an ADR behind, and no
  rule changes in the same commit as the work it governs.

**Negative / trade-offs**
- Added process rules have no record of the alternatives considered; the commit message and
  the Changelog entry are the only trail.
- The line between a convention and an architecture choice, and between clarifying a rule
  and relaxing it, needs judgement. When in doubt, write the ADR.

## Alternatives considered

- **Keep "via an ADR" for every section and follow it strictly** — rejected; an ADR per
  process tweak is more ceremony than a one-person project will sustain.
- **Leave the header as it was** — rejected; the rule and the practice would keep disagreeing.
- **Let process rules be edited directly in both directions** — the first draft of this ADR.
  Rejected the next day, before it was pushed: it made deleting a testing rule or a Definition of Done item as
  easy as adding one, with nothing requiring the owner's approval.
- **Drop ADRs for the constitution entirely** — rejected; stack decisions are exactly where
  the reasoning is worth keeping.
