# 002 — Regions — Tasks

**Status:** In Progress
**Plan:** [plan.md](./plan.md) (Approved 2026-11-10)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-002-n: <scenario>`.
Scenario-first (constitution §3.12): write the tests listed under a task first, see them
fail, then implement. T6 (markup-only page) may add its tests in the same commit.

## Phase A — Context

- [x] **T1** — `regions` table, `Region` schema, create and list (REQ-002-1, REQ-002-2) — done 2026-11-10
  - `mix ecto.gen.migration create_regions`: `name :citext`, `slug :string`,
    `active :boolean default true`, timestamps, unique indexes on `name` and `slug`,
    CHECK constraints `regions_slug_format` and `regions_name_length`
  - `lib/jairojobs/regions/region.ex`: `use Jairojobs.Schema`; `create_changeset/2`
    (trim, required, max 80, derive slug, `unique_constraint(:name)`,
    `unique_constraint(:slug, error_key: :name)`)
  - `lib/jairojobs/regions.ex`: `create_region/2` (admin scope only), `list_regions/0`
    (A→Z), `change_region/2`
  - `test/support/fixtures/regions_fixtures.ex`: `region_fixture/1` via `create_region/2`
  - Tests (`test/jairojobs/regions_test.exs`): `REQ-002-2: add a region`,
    `REQ-002-2: duplicate name` ("cebu", " Cebu "), `REQ-002-2: blank or too-long name`,
    `REQ-002-2: slug collision` ("Cebu!"), slug edge cases (diacritics, punctuation runs,
    symbols-only name), `REQ-002-1: admin sees all regions` (ordering),
    `REQ-002-2: non-admin scopes cannot add a region` (candidate, employer, `nil`, system)
  - Commit: `feat(regions): regions table, schema and create (REQ-002-1, REQ-002-2)`

- [x] **T2** — Rename (REQ-002-3) — done 2026-11-10
  - `Region.rename_changeset/2` (casts `:name` only); `Regions.rename_region/3`,
    `Regions.get_region!/1`
  - Tests: `REQ-002-3: rename keeps the slug`, `REQ-002-3: rename to an existing name`,
    `REQ-002-3: non-admin scopes cannot rename`, forged `slug` param is ignored
  - Commit: `feat(regions): rename a region, slug fixed (REQ-002-3)`

- [x] **T3** — Hide, show and the consumer contract (REQ-002-4, REQ-002-6) — done 2026-11-10
  - `Regions.hide_region/2`, `show_region/2`, `list_active_regions/0`,
    `get_region_by_slug/1`
  - Tests: `REQ-002-4: hide a region`, `REQ-002-4: unhide a region`,
    `REQ-002-4: hidden region keeps its data` (still exists, still resolves by slug; the
    listings half is tested in spec 003), `REQ-002-4: non-admin scopes cannot hide or show`,
    `REQ-002-6: only active regions are offered`,
    `REQ-002-6: lookup by slug works for hidden regions`, unknown slug returns `nil`
  - Commit: `feat(regions): hide/show and active-region contract (REQ-002-4, REQ-002-6)`

- [x] **T4** — Seed the launch regions (REQ-002-5) — done 2026-11-10
  - `Regions.seed_launch_regions/0` (match on slug, insert missing, `on_conflict: :nothing`)
  - `priv/repo/seeds.exs` calls it
  - Tests: `REQ-002-5: fresh install has the launch regions` (names, slugs, active),
    `REQ-002-5: seed is safe to run again` (rename "Cebu" to "Cebu City", reseed, no
    duplicates, rename kept), seed skips when another region already holds a launch name
  - `README.md`: one line on seeding under setup
  - Commit: `feat(regions): seed Davao City, Cebu, Metro Manila (REQ-002-5)`

## Phase B — Admin area

- [ ] **T5** — `require_admin` plug sends non-admins home (REQ-002-1; plan decision 1)
  - `UserAuth.require_admin/2`: for a signed-in non-admin, `put_flash(:error, "You are not
    authorized to access this page.")` and redirect to `/` instead of rendering 403; update
    the `@doc`
  - Tests (`test/jairojobs_web/user_auth_test.exs`): replace
    `REQ-001-9: candidate and employer get 403` with
    `REQ-002-1: non-admin is refused` (halted, redirected to `/`, flash set); admin and
    visitor tests unchanged
  - Add a line to spec 001 `tasks.md` notes pointing at this change
  - Commit: `feat(web): require_admin plug redirects non-admins home (REQ-002-1)`

- [ ] **T6** — Admin home and navigation link (REQ-002-1 rule)
  - Router: `live "/", HomeLive` inside the existing `live_session :require_admin`
  - `lib/jairojobs_web/live/admin/home_live.ex`: `<Layouts.app flash={@flash}
    current_scope={@current_scope}>`, `#admin-sections` with one row `#admin-section-regions`
    (the link target lands in T7)
  - `Layouts`: Admin item `href: ~p"/admin"`, placeholder removed
  - Tests: `test/jairojobs_web/live/admin/home_live_test.exs` — admin sees the Regions row,
    `REQ-002-1: non-admin is refused`, `REQ-002-1: visitor is redirected to log in`;
    `layouts_test.exs` — admin nav item links to `/admin` and is no longer a placeholder
  - Commit: `feat(web): admin home and nav link (REQ-002-1)`

- [ ] **T7** — Regions list with Hide / Show (REQ-002-1, REQ-002-4)
  - Router: `live "/regions", RegionLive.Index, :index`
  - `lib/jairojobs_web/live/admin/region_live/index.ex`: stream of regions, breadcrumb,
    `#add-region` (the one `btn-accent`), per row name + `/jobs/<slug>` + hidden badge +
    Edit + Hide or Show; `handle_event("hide" | "show")` → context → `stream_insert`;
    footer hint "Hidden regions stay on existing listings but can't be chosen."
  - Rows `min-h-11`, dividers, `max-w-[720px]`; check at 375 px
  - Tests (`test/jairojobs_web/live/admin/region_live_test.exs`):
    `REQ-002-1: admin sees all regions` (order by DOM position, `#region-hidden-<id>` on
    the inactive one), `REQ-002-1: non-admin is refused`,
    `REQ-002-1: visitor is redirected to log in`, `REQ-002-4: hide a region`,
    `REQ-002-4: unhide a region`
  - Commit: `feat(web): admin regions list with hide/show (REQ-002-1, REQ-002-4)`

- [ ] **T8** — New and Edit forms (REQ-002-2, REQ-002-3)
  - Router: `live "/regions/new", RegionLive.Form, :new`,
    `live "/regions/:id/edit", RegionLive.Form, :edit`
  - `lib/jairojobs_web/live/admin/region_live/form.ex`: `#region-form` with `<.input
    field={@form[:name]}>`, `validate` / `save` events, address hint on New, read-only
    `#region-address` on Edit, `#region-form-cancel`; on success flash + `push_navigate`
    to `/admin/regions`
  - Tests (`region_live_test.exs`): `REQ-002-2: add a region` (row appears, active),
    `REQ-002-2: duplicate name`, `REQ-002-2: blank or too-long name`,
    `REQ-002-2: slug collision`, `REQ-002-3: rename keeps the slug`,
    `REQ-002-3: rename to an existing name`, unknown id on Edit, non-admin refused on both
    routes
  - Commit: `feat(web): add and rename regions (REQ-002-2, REQ-002-3)`

## Phase C — Close

- [ ] **T9** — Docs and Definition of Done
  - `docs/architecture/diagrams/src/erd-jairojobs.puml`: add `regions`; run
    `scripts/render-diagrams.sh`; commit the SVG with it
  - `docs/architecture/data-model.md`: `regions` row → *Implemented*
  - `docs/architecture/overview.md`: `Jairojobs.Regions` → *Implemented*
  - `spec.md`, `plan.md`, `tasks.md` status → `Done`; feature map in spec 000 → Done
  - Walk the Definition of Done checklist (constitution §7) and record it below
  - Commit: `docs(spec 002): mark done`

## Definition of Done (constitution §7)

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
