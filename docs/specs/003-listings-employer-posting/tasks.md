# 003 — Listings: employer posting — Tasks

**Status:** In Progress
**Plan:** [plan.md](./plan.md) (Approved 2026-11-11)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-003-n: <scenario>`.
Scenario-first (constitution §3.12): write the tests listed under a task first, run them to
see them fail, then implement.

## Phase A — Accounts and the listing context

- [x] **T1** — Business details on the account (REQ-003-2) — done 2026-11-11
  - `mix ecto.gen.migration add_business_details_to_users`: `business_name`,
    `business_about`, CHECK `users_business_name_length`
  - `User`: fields + `business_changeset/2` (name required, trimmed, 2–80; about ≤ 500)
  - `Scope.poster?/1`
  - `Accounts.change_business_details/2`, `update_business_details/2`, `business_details?/1`
  - Tests (`accounts_test.exs`, `scope_test.exs`): `REQ-003-2: business name is required`
    (blank, 1 character, 81 characters), saves and trims, about over 500 refused,
    `REQ-003-2: a candidate cannot save business details`, `poster?/1` for all four roles
    and `nil`, the `users_business_name_length` CHECK refuses a direct bad update
  - Commit: `feat(accounts): business details for employers (REQ-003-2)`

- [ ] **T2** — `listings` table, `Pesos` type, save a draft, list and get (REQ-003-3, -13, -14)
  - `lib/jairojobs/pesos.ex`: cast digits / "14,000" / "₱14,000"; refuse decimals and text;
    dump ×100; load ÷100
  - `mix ecto.gen.migration create_listings`: columns, FKs (`on_delete: :restrict`), index
    `[:user_id, :status]`, the four CHECK constraints from the plan
  - `Listing` schema (`use Jairojobs.Schema`), `draft_changeset/2`
  - `Listings.create_listing/2`, `change_listing/2`, `list_my_listings/1`,
    `get_my_listing!/2`
  - `test/support/fixtures/listings_fixtures.ex`: `listing_fixture/2`,
    `complete_listing_attrs/1`, `employer_scope_fixture/1` (business details saved)
  - Tests (`pesos_test.exs`, `listings_test.exs`): `REQ-003-3: save an unfinished draft`,
    `REQ-003-3: title is required`, `REQ-003-3: a filled-in field must still be valid`
    (salary text, max below min, min below 1,000, max above 1,000,000, centavos, only one
    of the two, unknown type, over-long fields), `REQ-003-2: first post asks for business
    details` (`:business_details_required`), `REQ-003-1: a candidate cannot create a
    listing`, `REQ-003-14: my listings shows only mine`,
    `REQ-003-14: another employer's listing is not found` (`get_my_listing!/2`), forged
    `status` / `user_id` / `business_name` params ignored, the salary, status and
    employment-type CHECKs each refuse a direct bad update
  - Commit: `feat(listings): listings table and drafts (REQ-003-3, REQ-003-13, REQ-003-14)`

- [ ] **T3** — Edit and delete (REQ-003-5, -11)
  - `Listings.update_listing/3`, `delete_listing/2`
  - `ListingsFixtures.set_listing_status/3` (test-only; plan decision 1)
  - Tests: `REQ-003-5: edit a draft`, `REQ-003-5: editing a locked listing is refused`
    (pending, published, closed, taken down), a rejected listing can be edited,
    `REQ-003-11: delete a draft`, `REQ-003-11: delete a rejected listing`,
    `REQ-003-11: other listings cannot be deleted`,
    `REQ-003-14: another employer's listing is not found` (update, delete)
  - Commit: `feat(listings): edit and delete unpublished listings (REQ-003-5, REQ-003-11)`

- [ ] **T4** — Submit for approval and the limit (REQ-003-4, -6, -12)
  - `Listing.submit_changeset/1`; `Listings.missing_fields/1`, `submit_listing/2`
    (transaction, owner row lock, checks, business snapshot), `count_open_listings/1`,
    `open_listing_limit/1`
  - Tests: `REQ-003-4: complete listing`, `REQ-003-4: salary range is required`,
    `REQ-003-4: salary range must make sense`, `REQ-003-4: salary must be a real monthly
    amount`, description under 50 is incomplete, `REQ-003-6: submit a complete draft`
    (status, `submitted_at`, business snapshot), `REQ-003-6: incomplete draft cannot be
    submitted`, `REQ-003-6: region was hidden in the meantime`,
    `REQ-003-6: submitting twice does nothing`, `REQ-003-2: change business details`
    (snapshot unchanged on a Live listing, new name on the next submission),
    `REQ-003-12: within the limit`, `REQ-003-12: limit reached`,
    `REQ-003-12: drafts are not limited`, `REQ-003-12: admins are not limited`,
    `REQ-003-14` for submit, the completeness CHECK refuses a direct status change on an
    incomplete row, `REQ-002-4: hidden region keeps its data` (listings in every status are
    unchanged after their region is hidden — the half spec 002 deferred here)
  - `test/jairojobs/listings_concurrency_test.exs` (not async, unboxed): two concurrent
    submissions cannot exceed the limit
  - Commit: `feat(listings): submit for approval with free-tier limit (REQ-003-4, REQ-003-6, REQ-003-12)`

- [ ] **T5** — Withdraw, resubmit, close (REQ-003-7, -8, -9)
  - `Listings.withdraw_listing/2`, `close_listing/2`; resubmit path of `submit_listing/2`
    clears `rejection_reason`
  - Tests: `REQ-003-7: withdraw`, `REQ-003-7: only pending listings can be withdrawn`,
    `REQ-003-8: fix and resubmit` (reason cleared), `REQ-003-8: resubmit follows the same
    checks` (incomplete, limit), a rejected listing resubmits unchanged,
    `REQ-003-9: close` (`closed_at`), `REQ-003-9: only live listings can be closed`,
    `REQ-003-12: closing or withdrawing frees a place`, `REQ-003-14` for withdraw and close
  - Commit: `feat(listings): withdraw, resubmit and close (REQ-003-7, REQ-003-8, REQ-003-9)`

## Phase B — Screens

- [ ] **T6** — `require_poster` and the business details screen (REQ-003-1, -2)
  - `UserAuth`: `require_poster/2` plug and `on_mount(:require_poster, …)`
  - Router: `scope "/my", JairojobsWeb.Employer` with `live_session :require_poster`;
    `live "/business", BusinessLive, :edit`
  - `config/config.exs`: `config :phoenix, :filter_parameters, ["password", "listing",
    "business"]` (plan, Logging and privacy)
  - `Employer.BusinessLive`: `#business-form` with params under `business`; first save continues to the listing form
    (plain path until T8 adds the route), later saves go to My listings (plain path until T7)
  - Tests (`user_auth_test.exs`): employer and admin pass, candidate refused, visitor
    redirected — plug and hook. (`business_live_test.exs`):
    `REQ-003-2: business name is required`, saves, listing and business form values are
    filtered from logged parameters, `REQ-003-1: candidate is refused`,
    `REQ-003-1: visitor is redirected to log in`
  - Commit: `feat(web): poster access and business details screen (REQ-003-1, REQ-003-2)`

- [ ] **T7** — My listings and navigation (REQ-003-1, -13, -14)
  - `JairojobsWeb.Format.salary_range/2,3`; `ListingComponents.status_badge/1`
  - Router: `live "/listings", ListingLive.Index, :index`
  - `Employer.ListingLive.Index` per the wireframe
  - `Layouts`: Employer "My listings" → `/my/listings` ("Post a job" stays a placeholder
    until T8); `Admin.HomeLive`: "My listings" row
  - Tests (`format_test.exs`): `REQ-003-4: same minimum and maximum is allowed`, range and
    thousands separators. (`listing_live_test.exs`): `REQ-003-1: employer opens My
    listings`, `REQ-003-1: candidate is refused`, `REQ-003-1: visitor is redirected to log
    in` (and lands back after logging in), `REQ-003-13: see my listings` (order, labels),
    `REQ-003-13: unfinished draft in the list`, `REQ-003-13: limit is shown`, no limit line
    for an Admin, `REQ-003-13: no listings yet`, `REQ-003-14: my listings shows only mine`.
    (`layouts_test.exs`, `home_live_test.exs`): links updated
  - Commit: `feat(web): my listings and employer navigation (REQ-003-1, REQ-003-13)`

- [ ] **T8** — Listing form: new and edit (REQ-003-2, -3, -5)
  - Router: `live "/listings/new", ListingLive.Form, :new`,
    `live "/listings/:id/edit", ListingLive.Form, :edit`
  - `Employer.ListingLive.Form` per the wireframe (params under `listing`; the region
    select offers active regions plus the draft's own region when it has been hidden);
    redirect to `/my/business` when business details are missing; redirect to the owner view (plain path until T9) when the listing
    is locked
  - `Layouts`: "Post a job" → `/my/listings/new`; `Admin.HomeLive`: "Post a job" row;
    `#post-a-job` on My listings
  - Tests: `REQ-003-2: first post asks for business details`, `REQ-003-2: later posts skip
    the question`, `REQ-003-1: admin posts a listing`, `REQ-003-3: save an unfinished
    draft`, `REQ-003-3: title is required`, `REQ-003-3: a filled-in field must still be
    valid`, `REQ-003-3: only active regions are offered`, editing a draft whose region was
    hidden keeps the region, `REQ-003-5: edit a draft`,
    `REQ-003-5: editing a locked listing is refused` (edit address redirects),
    `REQ-003-14: another employer's listing is not found` (edit)
  - Commit: `feat(web): listing form for drafts (REQ-003-3, REQ-003-5)`

- [ ] **T9** — Owner view and its actions (REQ-003-6 to -12, -14)
  - `ListingComponents.listing_detail/1`
  - Router: `live "/listings/:id", ListingLive.Show, :show`
  - `Employer.ListingLive.Show`: status box, missing fields, rejection reason, actions by
    status, `data-confirm` on Close and Delete, flashes for each submit failure
  - Replace the plain paths from T6–T8 with verified routes
  - A Draft or Rejected listing shows the account's current business details; other
    statuses show the listing's own copy
  - Tests: `REQ-003-10: owner view of a draft` (current business name), `REQ-003-10: unfinished draft shows what is
    missing`, `REQ-003-10: actions follow the status`, `REQ-003-5: pending listing is
    locked`, `REQ-003-5: live listing is locked`, `REQ-003-6: submit a complete draft`,
    `REQ-003-6: incomplete draft cannot be submitted`, `REQ-003-6: region was hidden in the
    meantime`, `REQ-003-7: withdraw`, `REQ-003-8: see the reason`,
    `REQ-003-8: fix and resubmit`, `REQ-003-9: close`, `REQ-003-9: closing asks first`,
    `REQ-003-11: delete a draft`, `REQ-003-12: limit reached`,
    `REQ-003-14: another employer's listing is not found` (show)
  - Journey test — `test/jairojobs_web/live/employer/posting_journey_test.exs`, one
    `Phoenix.LiveViewTest` test, no browser (constitution §3.1), following every navigation
    and redirect with `follow_redirect/3` instead of opening pages directly:
    1. A logged-in Employer with no business details chooses "Post a job" in the menu and
       is sent to business details
    2. Saves the business name and lands on the listing form
    3. Saves a draft with only a title; the owner view says Draft and lists what is missing
    4. Edits it to be complete; the owner view shows the listing with salary and business name
    5. Submits; the status is Waiting for approval and My listings shows "1 of 3 open
       listings used"
    6. Withdraws, changes the title, resubmits
    7. (status set by the test helper until spec 004) rejected with a reason → sees the
       reason → resubmits; then published → closes it → Closed, "0 of 3 open listings used"
  - Check all four screens at 375 px in a headless browser
  - Commit: `feat(web): listing owner view and lifecycle actions (REQ-003-6..12)`

## Phase C — Close

- [ ] **T10** — Docs and Definition of Done
  - `docs/architecture/diagrams/src/erd-jairojobs.puml`: `listings`, the two new `users`
    columns, relationships; run `scripts/render-diagrams.sh`
  - `docs/architecture/data-model.md`, `overview.md`: `listings` and `Jairojobs.Listings`
    → *Implemented (employer side)*
  - `README.md`: one paragraph on posting a listing in development
  - Push; CI green on `main`; `spec.md`, `plan.md`, `tasks.md` → `Done`; feature map → Done
  - Commit: `docs(spec 003): mark done`

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
