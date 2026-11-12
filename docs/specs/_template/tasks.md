# NNN — <Feature name> — Tasks

**Status:** Draft
**Plan:** [plan.md](./plan.md)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-NNN-n: <scenario>`.
Scenario-first (constitution §3.12): write the tests listed under a task first, run them to
see them fail, then implement. Mark a finished task `[x]` with `— done YYYY-MM-DD`.

## Tasks

- [ ] **T1** — <migration + schema> (REQ-NNN-1)
  - 
- [ ] **T2** — <context functions + tests> (REQ-NNN-1)
  - 
- [ ] **T3** — <LiveView + tests> (REQ-NNN-1, REQ-NNN-2)
  - 
- [ ] **T4** — <wire routes, nav, auth> 
- [ ] **T5** — update `docs/architecture/` if data model or boundaries changed
- [ ] **T6** — push; CI green on `main`; set spec, plan and tasks status to `Done`; feature
  map in spec 000 → Done

## Definition of Done (constitution §7)

<!-- Walk this at the end and say how each item was met (test counts, CI run, what was checked
     at 375 px). Leave an item unchecked, with the reason, if it cannot be met yet. -->

- [ ] Every REQ in the spec has a passing, REQ-named test
- [ ] Authorization tests present for any private resource
- [ ] `mix precommit` green locally **and** CI green on `main`
- [ ] Works at 375 px width (phone) before desktop
- [ ] No new deps without a justification line in `plan.md`
- [ ] `docs/architecture/` updated if contexts or data model changed
- [ ] `tasks.md` checked off; spec status set to `Done`
- [ ] Deployed to Fly.io (once deployment exists) and smoke-checked

## Notes / deviations from plan

<!-- Record anything that changed during implementation and why. -->

- 
