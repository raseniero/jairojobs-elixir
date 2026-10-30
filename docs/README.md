# jairojobs — Documentation

This folder is the single source of truth for *what* we build and *why*.
Code lives in `lib/`; intent lives here.

## Layout

| Path | Purpose |
|---|---|
| `constitution.md` | Non-negotiable project principles: stack, testing, conventions, how specs are written |
| `specs/NNN-name/` | One folder per feature: `spec.md` (what/why) → `plan.md` (how) → `tasks.md` (steps) |
| `specs/_template/` | Copy this to start a new feature |
| `specs/000-product-overview/` | Root spec: vision, personas, glossary, feature map |
| `decisions/` | Architecture Decision Records (ADRs), numbered, immutable once accepted |
| `architecture/` | Living overview of contexts, boundaries, and data model |

## Feature lifecycle

```
spec.md  ──►  plan.md  ──►  tasks.md  ──►  code + tests  ──►  Done
 (WHAT/WHY)     (HOW)       (STEPS)
```

1. **Spec** — copy `specs/_template/` to `specs/NNN-kebab-name/`. Fill in `spec.md` only.
   No implementation detail here; user stories and acceptance criteria.
2. **Plan** — once the spec is `Approved`, write `plan.md`: contexts, schemas, routes,
   LiveViews, migrations, test strategy.
3. **Tasks** — break the plan into `tasks.md`: ordered, checkable, each small enough for one commit.
4. **Implement** — work through tasks. Reference requirement IDs in test names and commit messages.
5. **Close** — set status to `Done`; update `architecture/` if boundaries or data model changed.

## Conventions

### Numbering
- Specs: `NNN-kebab-name`, three digits, starting at `001`. `000` is reserved for the product overview.
- ADRs: `NNNN-kebab-name`, four digits, starting at `0001`.

### Status (header of every spec / plan / ADR)
`Draft` → `Approved` → `In Progress` → `Done`
(ADRs use `Proposed` → `Accepted` → `Superseded by NNNN`)

### User story IDs
Format: `US-<spec#>-<n>`, e.g. `US-001-2` is the second user story of spec 001.
- Never renumber; mark removed ones as `(dropped)`.
- Each requirement lists the stories it serves (`**Serves:** US-001-2, US-001-3`).
- Every spec ends with a traceability table (story → requirements) so gaps are visible.

### Requirement IDs
Format: `REQ-<spec#>-<n>`, e.g. `REQ-001-3` is the third requirement of spec 001.
- Never renumber; mark removed ones as `(dropped)`.
- Reference in ExUnit test names: `test "REQ-001-3: user can reset password"`.
- Reference in commits: `feat(auth): password reset (REQ-001-3)`.

### Acceptance criteria
Written as Given / When / Then. Each criterion should map to at least one test.

### Diagrams
Text sources only; never commit binary-only diagrams.

| Use | Tool | Location |
|---|---|---|
| Simple diagrams (flows, state machines, small ERDs) | **Mermaid**, inline in the `.md` | wherever it's discussed |
| Richer diagrams (C4, detailed ERD, sequence with notes, deployment) | **PlantUML** `.puml` | `architecture/diagrams/src/` |

PlantUML sources are rendered to **SVG** in `architecture/diagrams/out/` via
`scripts/render-diagrams.sh` and embedded with `![title](diagrams/out/name.svg)`.
Regenerate and commit the SVG in the same commit as the `.puml` change.
SVG (not PNG): vector, small, diffable, text stays searchable. Avoid `skinparam` options
that embed fonts — GitHub strips them.

### ADRs
Short. Status / Context / Decision / Consequences. Once `Accepted`, do not edit —
write a new ADR that supersedes it.

## Relationship to other files
- `AGENTS.md` (repo root) — Phoenix/Elixir coding conventions for AI agents; points here.
- `scratchpad/` (gitignored) — throwaway working notes. Promote anything durable into `docs/`.
