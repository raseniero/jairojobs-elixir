# NNN — <Feature name> — Plan

**Status:** Draft
**Spec:** [spec.md](./spec.md) (must be `Approved`)
**Created:** YYYY-MM-DD
<!-- Add `**Approved:** YYYY-MM-DD` under Created when the plan is approved. -->

## Approach

<!-- 2–5 sentences. The shape of the solution and the main trade-off made. -->

## Contexts & modules

<!-- Which Phoenix contexts are touched or created. e.g. Jairojobs.Jobs, Jairojobs.Accounts -->

| Module | New / Changed | Responsibility |
|---|---|---|
| `Jairojobs.<Context>` | New | |

## Data model

<!-- Schemas, fields, associations, indexes, constraints. Mermaid erDiagram welcome. -->

```mermaid
erDiagram
```

### Migrations

- 

## Routes & LiveViews / Controllers

| Method / Live | Path | Module | Auth |
|---|---|---|---|
| live | `/...` | `JairojobsWeb.<Name>Live.Index` | |

<!-- For every route say which scope, pipeline and `live_session` it goes in, and why. -->

### DOM ids (fixed now so tests can be written first)

<!-- constitution §3.12: decide the ids of key elements before writing LiveView tests. -->

| Element | id |
|---|---|
| | `#...` |

## Authorization

<!-- Who can do what. Scopes. -->

- 

## Background jobs / emails / external services

- 

## Test strategy

<!-- Map REQ IDs to test modules. -->

| Requirement | Test location | Type |
|---|---|---|
| REQ-NNN-1 | `test/jairojobs/...` | context |
| REQ-NNN-1 | `test/jairojobs_web/live/...` | LiveView |

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| | |

## Decisions to confirm

<!-- Choices the owner should confirm before implementation. Rename to
     "Decisions confirmed (YYYY-MM-DD)" and change "Proposed" to "Choice" on approval. -->

| # | Decision | Proposed | Hard to change later? |
|---|---|---|---|
| 1 | | | |

## Alternatives considered

- 
