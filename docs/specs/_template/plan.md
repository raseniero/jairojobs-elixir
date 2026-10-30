# NNN — <Feature name> — Plan

**Status:** Draft
**Spec:** [spec.md](./spec.md) (must be `Approved`)
**Created:** YYYY-MM-DD

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

- 

## Alternatives considered

- 
