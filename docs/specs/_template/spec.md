# NNN — <Feature name>

**Status:** Draft
**Created:** YYYY-MM-DD
**Owner:** 
**Related ADRs:** 

## Problem / Why

<!-- One or two paragraphs. What problem does this solve, for whom, and why now? -->

## Goals

- 

## Non-goals / Out of scope

- 

## Personas involved

<!-- Reference docs/specs/000-product-overview/spec.md -->

- 

## User stories

<!-- One clause per line. Keep the three-part shape. -->

**US-NNN-1**
- As a <persona>,
- I want <goal>,
- so that <benefit>.

**US-NNN-2**
- As a <persona>,
- I want <goal>,
- so that <benefit>.

## Screen flow

<!-- Required if the spec has user-facing screens. Every user story must have a row. -->

![Screen flow](diagrams/screenflow-<subject>.svg)

| Story | Path through the screen flow |
|---|---|
| US-NNN-1 | <screen> → <screen> → … |

## Flows (activity diagrams)

<!-- Every REQ must appear in exactly one row. 3–6 flows per spec. Sources in ./diagrams/ -->

| Flow | Covers | Diagram |
|---|---|---|
| <flow name> | REQ-NNN-1, REQ-NNN-2 | [activity-<name>](diagrams/activity-<name>.svg) |

### <Flow name>
![<Flow name>](diagrams/activity-<name>.svg)

## Requirements

### REQ-NNN-1: <short title>

**Serves:** US-NNN-1

<!-- Narrative, one or two sentences. -->

```gherkin
Scenario: <short name — becomes the test name>
  Given <precondition>
  When <action>
  Then <observable result>
  And <additional result>

Scenario: <failure or edge case>
  Given <precondition>
  When <action>
  Then <observable result>
```

**Rules**
<!-- Constraints that aren't a scenario (limits, invariants). Omit if none. -->
- 

### REQ-NNN-2: <short title>

**Serves:** US-NNN-1, US-NNN-2

```gherkin
Scenario: <short name>
  Given <precondition>
  When <action>
  Then <observable result>
```

## Non-functional requirements

<!-- Performance, security, accessibility, i18n, etc. specific to this feature. Omit if none. -->

- 

## Open questions

- 

## Traceability

| Story | Requirements |
|---|---|
| US-NNN-1 | REQ-NNN-1, REQ-NNN-2 |
| US-NNN-2 | REQ-NNN-2 |

## Changelog

| Date | Change |
|---|---|
| YYYY-MM-DD | Created |
