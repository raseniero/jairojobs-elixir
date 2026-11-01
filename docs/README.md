# jairojobs — Documentation

This folder is the single source of truth for *what* we build and *why*.
Code lives in `lib/`; intent lives here.

## Layout

| Path | Purpose |
|---|---|
| `constitution.md` | Non-negotiable project principles: stack, testing, conventions, how specs are written |
| `design.md` | Design guide: principles, tokens, daisyUI theme, UI patterns, do/don't. Reference render in `design/` |
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
- Reference in ExUnit test names: `test "REQ-001-3: <scenario name>"`.
- Reference in commits: `feat(auth): password reset (REQ-001-3)`.

### Writing style

**User stories** — one clause per line as a bullet triplet:
```
**US-001-1**
- As a Visitor,
- I want to browse listings without creating an account,
- so that I can see if the site is useful before committing.
```

**Acceptance criteria** — Gherkin inside a ```` ```gherkin ```` fenced block (GitHub and
editors highlight the keywords). One `Scenario:` per case; the scenario name becomes the
test name. Use `And` / `But` for additional steps.
```gherkin
Scenario: Protected page redirects and returns
  Given I am not logged in
  When I open a protected page such as Settings
  Then I am redirected to the log-in page
  And after logging in I land on the page I originally asked for
```
Each scenario should map to at least one test:
`test "REQ-001-1: protected page redirects and returns"`.

Constraints that aren't scenarios (limits, invariants) go under a **Rules** label inside the
requirement, outside the Gherkin block, so they can use inline code and links.

### Diagrams
Text sources only; never commit binary-only diagrams.

| Use | Tool | Location |
|---|---|---|
| Simple diagrams (flows, state machines, small ERDs) | **Mermaid**, inline in the `.md` | wherever it's discussed |
| Richer diagrams (C4, detailed ERD, sequence with notes, deployment) | **PlantUML** `.puml` | architecture-level: `architecture/diagrams/src/`; spec-level: `specs/NNN-name/diagrams/` |

PlantUML sources are rendered to **SVG** by `scripts/render-diagrams.sh`:
architecture diagrams go to `architecture/diagrams/out/`; spec diagrams render in place next
to their `.puml`. Embed with `![title](diagrams/name.svg)` (spec) or
`![title](diagrams/out/name.svg)` (architecture).
Regenerate and commit the SVG in the same commit as the `.puml` change.
SVG (not PNG): vector, small, diffable, text stays searchable. Avoid `skinparam` options
that embed fonts — GitHub strips them.

**File naming:** `<type>-<subject>.puml`, lowercase kebab-case; the `.svg` shares the name and
`@startuml <name>` (or `@startsalt <name>`) matches the filename.

| Type prefix | Diagram |
|---|---|
| `usecase-` | use case |
| `c4-context-`, `c4-container-`, `c4-component-` | C4 levels |
| `erd-` | entity-relationship |
| `state-` | state machine |
| `sequence-` | sequence |
| `activity-` | activity |
| `wireframe-` | Salt wireframe (single screen layout) |
| `screenflow-` | screen flow: screens as states, user actions as arrows |
| `deployment-` | deployment |

Subject is what the diagram is about (`signup`, `account`, `nav`); the single project-wide
instance uses `-product`, `-system`, or `-jairojobs` (e.g. `usecase-product`, `erd-jairojobs`).

**Which diagram, when** (keep this lean — a diagram must earn its place):

1. **State diagrams are mandatory** for any entity with a lifecycle (Listing, Application).
   They live in the owning `spec.md`; the Gherkin scenarios must agree with the diagram.
2. **Sequence diagrams only for flows touching ≥ 3 parties** (e.g. anything involving email or
   an external service). Live in `plan.md`. Simple LiveView → context → DB flows need none.
3. **Architecture-level diagrams** — use case, C4 / component, deployment, ER — live in
   `architecture/diagrams/` and are updated as part of a spec's Definition of Done when they
   change.
4. **Prefer ER (`entity`) over Class** for persisted data; Class only for in-memory structures
   (e.g. `Scope`).
5. **Every requirement is covered by an activity diagram.** Group related requirements into
   one flow per diagram (e.g. "sign up and confirm", "settings") rather than one per REQ;
   aim for 3–6 diagrams per spec. They live in `spec.md` under a "Flows" section with a
   table mapping each diagram to the REQs it covers. No swimlanes — name the actor in the
   step text instead; they tangle once a flow branches. Object diagrams remain opt-in.
6. **Wireframes (Salt) are optional in `spec.md`** for a new screen; sketch the 375 px layout
   before building when it isn't obvious. Not a substitute for the real UI.
7. **Every spec with user-facing screens has one screen-flow diagram** (`screenflow-<subject>`):
   a state diagram where each state is a screen listing its key elements and each arrow is a
   user action. It sits in `spec.md` with a table mapping every user story to its path. Shade
   public screens, emails, and operator/terminal steps differently. Keep per-screen layout
   detail in Salt wireframes, not in the flow.

Not used: timing, composite structure, Gantt, mind map / WBS, JSON/YAML renders.

### ADRs
Short. Status / Context / Decision / Consequences. Once `Accepted`, do not edit —
write a new ADR that supersedes it.

## Relationship to other files
- `AGENTS.md` (repo root) — Phoenix/Elixir coding conventions for AI agents; points here.
- `scratchpad/` (gitignored) — throwaway working notes. Promote anything durable into `docs/`.
