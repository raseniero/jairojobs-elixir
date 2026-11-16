# 004 — Listings: admin moderation — Tasks

**Status:** In Progress
**Plan:** [plan.md](./plan.md) (Approved 2026-11-16)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-004-n: <scenario>`.
Scenario-first (constitution §3.12): write the tests listed under a task first, run them to
see them fail, then implement. Mark a finished task `[x]` with `— done YYYY-MM-DD`.

Run `mix precommit` with `set -o pipefail` (or read its output) before each commit: piping
it through `tail` hides a failing exit status.

Tests use the fixtures' unique titles, business names and regions so they can stay
`async: true`. The only non-async modules are the three the plan names: the concurrency
test and the two mail-failure tests, each with a comment saying why.

Earlier documents: the spec's table "Earlier documents this spec changes" is split across
the tasks below, so each document changes in the commit that builds the behaviour it
describes. Every such change gets a changelog row in the document changed, and every
changed `.puml` is rendered on its own (`plantuml -tsvg file.puml`), not with the
render-all script.

## Phase A — The context

- [x] **T1** — Decision columns; approve, reject, take down (REQ-004-5, -6, -7; part of -1) — done 2026-11-16
  - `mix ecto.gen.migration add_moderation_to_listings`: `takedown_reason`, `published_at`,
    `decided_at`, `decided_by_id` (`on_delete: :nilify_all`),
    `index(:listings, [:status, :submitted_at])`. No CHECKs yet (they are T3)
  - `Listing`: the four fields, `belongs_to :decided_by`; `approve_changeset/3`,
    `reject_changeset/4`, `take_down_changeset/4`; `submit_changeset/3` also clears
    `decided_at` and `decided_by_id`
  - `Listings.change_reason/1` (schemaless: `reason`, trimmed, 10–500)
  - `Listings.approve_listing/3`, `reject_listing/4`, `take_down_listing/4` with their
    final signatures and return shape. The address function is accepted and not yet used;
    `email` is always `:own_listing` until T7
  - One private helper for all three: transaction, re-read the acting account's role, lock
    the listing row, read it fresh
  - The status helper `set_listing_status/3` is **not** touched in this task
  - Tests (`test/jairojobs/listings_moderation_test.exs`, new, async). Listings are built
    with the real `create_listing` → `submit_listing`, not the status helper:
    `REQ-004-5: approve` (status, `published_at`, `decided_at`, `decided_by_id`),
    `REQ-004-5: approving does not change the listing`,
    `REQ-004-5: hidden region blocks approval`,
    `REQ-004-5: listing is no longer waiting` (withdrawn → `:not_pending`, not
    `:not_found`; already approved; already rejected),
    `REQ-004-5: admin approves their own listing`,
    `REQ-004-6: reject with a reason` (reason trimmed, decision recorded),
    `REQ-004-6: a reason is required` (none, 9 characters, 501 characters, spaces only),
    `REQ-004-6: only a waiting listing can be rejected`,
    `REQ-004-6: rejecting frees a place`,
    `REQ-004-7: take down with a reason` (`published_at` kept, `decided_at` moved),
    `REQ-004-7: a reason is required`,
    `REQ-004-7: only a live listing can be taken down`,
    `REQ-004-7: taken down is final` (approve, submit, withdraw, close and owner edit all
    refused), `REQ-004-7: taking down frees a place`,
    `REQ-004-1: only an Admin can decide` (Employer who owns the listing, another Employer,
    a Candidate, `nil`; approve, reject, take down; the listing is unchanged each time),
    an Admin demoted after their scope was built is refused, a resubmission clears the
    previous decision, a deleted listing gives `:not_found`, forged `status` /
    `decided_by_id` / `published_at` in the reason params are ignored
  - Commit: `feat(listings): approve, reject and take down (REQ-004-5, REQ-004-6, REQ-004-7)`

- [x] **T2** — Retire the test-only status helper (plan decision 8) — done 2026-11-16
  - `ListingsFixtures`: delete `set_listing_status/3`. `listing_in_status_fixture/3` reaches
    each status through the real functions with a throwaway Admin: submit; approve; reject
    (`:reason` option, default "Needs more detail"); approve then close; approve then take
    down
  - Replace every direct use of `set_listing_status/3` in `listings_test.exs`,
    `listing_live_test.exs` and `posting_journey_test.exs` (context calls for now; the
    journey gets real Admin screens in T13)
  - **Nothing else in this commit.** No new behaviour, no new tests. All existing tests
    must pass, so a failure points at the swap alone
  - Commit: `test(listings): reach every status through the real moderation functions`

- [ ] **T3** — Database checks for decisions (plan decision 12)
  - `mix ecto.gen.migration add_moderation_checks_to_listings`:
    `listings_published_has_time`, `listings_rejected_has_reason`,
    `listings_taken_down_has_reason`, with a comment that no earlier rows can break them
  - `check_constraint/3` for each on the matching changeset
  - Tests (`listings_moderation_test.exs`): each CHECK refuses a direct bad update
  - Docs: ERD (the four columns, the new relationship, the three checks, and the planning
    comment moves `published_at` from 005 to 004) and `data-model.md`
  - Commit: `feat(listings): database checks for moderation decisions (REQ-004-5, REQ-004-6, REQ-004-7)`

- [ ] **T4** — Lock the listing row on every status change (plan decision 11)
  - `withdraw_listing/2`, `close_listing/2`, `update_listing/3`, `delete_listing/2` run in
    a transaction and use the row-lock helper from T1; `submit_listing/2` locks the
    listing row after the owner row
  - Tests (`test/jairojobs/listings_concurrency_test.exs`, not async, unboxed, cleans up
    its rows): approve and withdraw at the same moment leave either a Draft with no
    decision or a Published listing with one, never a mix. Confirm the test fails with the
    lock removed, then restore it
  - Spec 003's existing tests must pass unchanged
  - Commit: `fix(listings): lock the listing row on every status change`

- [ ] **T5** — The queue, the status lists and the Admin's read (REQ-004-2, -3, -4)
  - `Listings.count_pending_listings/1`, `list_listings_for_moderation/3`,
    `get_listing_for_moderation!/2` (region, owner and deciding Admin preloaded)
  - Tests (`listings_moderation_test.exs`): `REQ-004-2: longest-waiting first`,
    `REQ-004-2: drafts are not in the queue`,
    `REQ-004-2: a withdrawn listing leaves the queue`, a resubmitted listing goes to the
    back, an Admin edit does not move a listing (completed in T6),
    `REQ-004-3: choose a status` (each of the four, most recently changed first),
    `REQ-004-3: a long list is shown in parts` (60 listings: 50 and `more? == true`, then
    10 and `false`), asking for `:draft` returns nothing,
    `REQ-004-4: a Draft is not found` (Draft, withdrawn, unknown id, malformed id),
    a non-Admin gets `0`, `{[], false}` and `Ecto.NoResultsError`
  - Commit: `feat(listings): approval queue and moderation lists (REQ-004-2, REQ-004-3, REQ-004-4)`

- [ ] **T6** — Admin edit (REQ-004-8; rest of -1)
  - `Listing.admin_changeset/2`; `Listings.change_listing_as_admin/2`,
    `update_listing_as_admin/4` (final shape; `email` is `:own_listing` until T7)
  - Tests (`listings_moderation_test.exs`): `REQ-004-8: fix a waiting listing` (status and
    `submitted_at` unchanged, same place in the queue),
    `REQ-004-8: fix a live listing`,
    `REQ-004-8: the listing must stay complete` (each required field emptied, bad salary,
    description under 50, business name of 1 and 81 characters, "about" over 500),
    `REQ-004-8: business name changes on the listing only`,
    `REQ-004-8: other listings cannot be edited` (Rejected, Closed, Taken down),
    `REQ-004-8: only active regions can be chosen` (keep the hidden one, move to an active
    one, another hidden one refused),
    `REQ-004-8: saving without changes does nothing` (`:unchanged`, `updated_at` untouched),
    `REQ-004-8: the listing changed while I was editing` (withdrawn → `:not_editable`),
    the later of two saves wins, the decision columns are untouched by an edit, forged
    `status` / `user_id` / `submitted_at` ignored,
    `REQ-004-1: only an Admin can decide` extended to the edit
  - Docs: spec 003 REQ-003-5 (rule reworded for the Employer), REQ-003-2 (the Admin-edit
    exception), spec 003 `state-listing` ("locked for the Employer"); changelog rows
  - Commit: `feat(listings): admin edit of waiting and live listings (REQ-004-8)`

- [ ] **T7** — Decision emails (REQ-004-9)
  - `Jairojobs.Listings.ListingNotifier`: `deliver_approved/3`, `deliver_rejected/3`,
    `deliver_taken_down/3`, `deliver_edited/4`; the short-name map for changed parts
  - The four actions send after the transaction commits; `email` becomes `:sent`,
    `:own_listing` or `:failed`; an error or a raise is caught and logged with the listing
    id and the kind of email only
  - `test/support`: `Jairojobs.FailingMailAdapter` (returns an error) and a raising variant
  - `ListingsFixtures`: empty the test mailbox of `{:email, _}` before returning
  - Tests (`listings_moderation_test.exs`): `REQ-004-9: approved email` (recipient, sender,
    subject, title, link to `/my/listings/<id>`),
    `REQ-004-9: rejected email carries the reason` (and "edited and sent again"),
    `REQ-004-9: taken-down email carries the reason`,
    `REQ-004-9: edit email names what changed` ("Job title" and "Area"; both salary ends
    read "Salary" once; no old or new text in the body),
    `REQ-004-9: no email for your own action` (all four, `refute_email_sent`), an Admin
    acting on another Admin's listing does email that Admin, an unchanged edit sends
    nothing, an owner who has since been demoted to Candidate is still emailed. (`test/jairojobs/listings_email_failure_test.exs`, new, `async: false` with a
    comment): `REQ-004-9: the decision stands if the email cannot be sent` (error adapter
    and raising adapter; status saved, `:failed` returned, the log has the id and not the
    address, title or reason)
  - Commit: `feat(listings): email the owner each moderation decision (REQ-004-9)`

## Phase B — Screens

- [ ] **T8** — Admin Listings page, the Admin area row, the time helper (REQ-004-1, -2, -3)
  - `JairojobsWeb.Format.time_ago/2`, `manila_date/1`
  - Router, in the existing `/admin` scope and `live_session :require_admin`:
    `live "/listings", ListingLive.Index, :index`
  - `Admin.ListingLive.Index`: five status links (`?status=`), the count, the stream, the
    empty sentences, "Your listing", "Show more". Rows link to the Admin view by a plain
    path with `?from=` until T9 adds the route
  - `Admin.HomeLive`: "Listings" as the first row, with "2 waiting for approval" or
    "Nothing waiting"
  - Tests (`format_test.exs`): just now, minutes, hours, days, exactly 7 days, a date that
    falls on the next day in Manila. (`test/jairojobs_web/live/admin/listing_live_test.exs`,
    new): `REQ-004-1: admin opens Listings`,
    `REQ-004-1: employer or candidate is refused`,
    `REQ-004-1: visitor is redirected to log in` (and lands back after logging in),
    `REQ-004-2: longest-waiting first`, `REQ-004-2: what a row shows`,
    `REQ-004-2: empty queue`, `REQ-004-2: my own listing is marked`,
    `REQ-004-2: the Admin area shows how many are waiting` (the count on the Listings page),
    `REQ-004-3: choose a status`, `REQ-004-3: each status can be chosen`,
    `REQ-004-3: nothing with that status` (each of the four sentences),
    `REQ-004-3: a long list is shown in parts` ("Show more" appends 10 and then
    disappears), rows outside the queue say when they last changed, an unknown `?status=`
    shows the queue. (`home_live_test.exs`):
    `REQ-004-2: the Admin area shows how many are waiting` (the row),
    `REQ-004-2: nothing waiting`, row order
  - Docs: spec 002 `screenflow-regions` (the Admin screen gains "Listings" as its first
    row), spec 001 `wireframe-nav` (the note on what the Admin area holds); changelog rows
  - Commit: `feat(web): admin listings page and waiting count (REQ-004-1, REQ-004-2, REQ-004-3)`

- [ ] **T9** — Admin view and Approve (REQ-004-4, -5; rest of -3)
  - Router: `live "/listings/:id", ListingLive.Show, :show`; the row links from T8 become
    verified routes
  - `Admin.ListingLive.Show`: the box (status, "Your listing", poster, submitted time,
    latest decision and reason, hidden-region line, the one-sentence help), then
    `listing_detail` with the listing's own business copy; `#approve-listing`; the back
    link from `?from=`; messages and landings per the plan, including a refusal for a
    listing that can no longer be shown
  - Tests (`admin/listing_live_test.exs`): `REQ-004-4: review a waiting listing`,
    `REQ-004-4: the latest decision is shown` (rejected, with the Admin's email and reason;
    none after a resubmission), `REQ-004-4: a hidden region is flagged` (pill, sentence,
    Approve still there; a Live listing in a hidden region shows the pill without the
    sentence), `REQ-004-4: a Draft is not found`,
    `REQ-004-1: employer or candidate is refused` and
    `REQ-004-1: visitor is redirected to log in` for the Admin view's address,
    `REQ-004-3: back returns to the same list`, no `from` goes back to the queue,
    `REQ-004-5: approve` (lands on the queue with the message; the Employer's My listings
    shows Live), `REQ-004-5: hidden region blocks approval`,
    `REQ-004-5: listing is no longer waiting` (withdrawn in the meantime → the queue with
    the message; approved by another Admin → the Admin view with the message),
    `REQ-004-5: admin approves their own listing`, Approve has no confirm step, the help
    sentence leaves out "and emails the employer" on the Admin's own listing, a listing
    deleted in the meantime sends the Admin to the queue with "That listing is not
    available."
  - (`test/jairojobs_web/live/moderation_email_failure_test.exs`, new, `async: false`
    with a comment, failing adapter): approving shows "Approved. It is live. The employer
    could not be emailed." and the listing is Live
  - Commit: `feat(web): admin view of a listing and approve (REQ-004-4, REQ-004-5)`

- [ ] **T10** — Reject and take down (REQ-004-6, -7)
  - Router: `live "/listings/:id/reject", ListingLive.Show, :reject`,
    `live "/listings/:id/take-down", ListingLive.Show, :take_down`
  - `Admin.ListingLive.Show`: `#reject-listing` and `#take-down-listing`; the reason form
    (`#decision-form`, params under `decision`, error-style submit, Cancel); a wrong-status
    address redirects to the Admin view with the message
  - `config/config.exs`: `"decision"` added to `:filter_parameters`
  - `Employer.ListingLive.Show`: `#listing-takedown-reason` in the status box
  - Tests (`admin/listing_live_test.exs`): `REQ-004-6: reject with a reason` (lands on the
    queue; the Employer's owner view shows "Needs changes" and the reason),
    `REQ-004-6: a reason is required`,
    `REQ-004-6: only a waiting listing can be rejected` (form address for a Live listing;
    withdrawn while the form is open), "The employer will see this." is on the form,
    `REQ-004-7: take down with a reason` (stays on the Admin view, now Taken down),
    `REQ-004-7: a reason is required`, `REQ-004-7: taking down asks first`,
    `REQ-004-7: only a live listing can be taken down`,
    `REQ-004-7: taken down is final` (no action element on the Admin view or the owner
    view), Cancel returns to the Admin view. (`employer/listing_live_test.exs`): the
    take-down reason is shown to the owner. (`endpoint_log_test.exs`): a posted reason is
    not in the log. (`moderation_email_failure_test.exs`): the reject and take-down
    messages end with " The employer could not be emailed." 
  - Docs: spec 003 REQ-003-10, `activity-my-listings`, `activity-after-submitting` (the
    Taken down case), `screenflow-posting`, `wireframe-posting`; changelog row
  - Commit: `feat(web): reject and take down with a reason (REQ-004-6, REQ-004-7)`

- [ ] **T11** — Admin edit form (REQ-004-8; rest of -4)
  - `ListingComponents.listing_fields/1`, moved out of the Employer form;
    `Employer.ListingLive.Form` uses it with no change in behaviour
  - Router: `live "/listings/:id/edit", ListingLive.Form, :edit`
  - `Admin.ListingLive.Form`: the shared fields plus business name and "about", the fixed
    sentence, region options with the listing's own hidden region; `#admin-edit-listing`
    on the Admin view; a wrong-status address redirects with the message
  - Tests (`admin/listing_live_test.exs`): `REQ-004-8: fix a waiting listing`,
    `REQ-004-8: fix a live listing` (both land on the Admin view with the message),
    `REQ-004-8: the listing must stay complete`,
    `REQ-004-8: business name changes on the listing only`,
    `REQ-004-8: other listings cannot be edited` (the edit address redirects),
    `REQ-004-8: only active regions can be chosen`,
    `REQ-004-8: saving without changes does nothing`,
    `REQ-004-8: the listing changed while I was editing`,
    `REQ-004-4: actions follow the status` (all five statuses, now that every action
    exists), the sentence "The employer will be told what you changed." is on the form,
    a save with nothing changed lands on the Admin view with "Nothing was changed.".
    (`moderation_email_failure_test.exs`): "Changes saved. The employer could not be
    emailed." Spec 003's form tests pass unchanged
  - Docs: `architecture/overview.md` (the five `/admin/listings` routes; Listings context
    → moderation implemented)
  - Commit: `feat(web): admin edit form (REQ-004-8)`

- [ ] **T12** — Emails to Admins on submission (REQ-004-10)
  - `ListingNotifier.deliver_submitted/3`; `Listings.submit_listing/3` emails every Admin
    except the submitter after it commits, and never fails because of it
  - `Employer.ListingLive.Show` passes the Admin-view address; the 28 test call sites of
    `submit_listing` and the fixtures are updated
  - Tests (`listings_moderation_test.exs`). These build their own Drafts and submit them,
    and assert on named recipients, not on a count (fixtures create Admins):
    `REQ-004-10: submission emails the Admins` (subject, title, business, region, link to
    `/admin/listings/<id>`, nothing else from the listing),
    `REQ-004-10: a resubmission emails the Admins again`,
    `REQ-004-10: the Admin who submitted is not emailed`,
    `REQ-004-10: withdrawing sends nothing`, a refused submission sends nothing.
    (`listings_email_failure_test.exs`):
    `REQ-004-10: the submission stands if the email cannot be sent`.
    (`moderation_email_failure_test.exs`): the Employer sees the usual "Submitted…"
    message when the email to Admins fails
  - Docs: spec 003 REQ-003-6 and REQ-003-8, `activity-submit-for-approval`,
    `activity-after-submitting` (the resubmit branch); changelog row
  - Commit: `feat(listings): email admins when a listing is submitted (REQ-004-10)`

- [ ] **T13** — Journey test and the phone check
  - `test/jairojobs_web/live/moderation_journey_test.exs`, one `Phoenix.LiveViewTest`
    test, no browser (constitution §3.1), following every navigation and redirect:
    1. An Employer posts a complete listing and submits it; the Admin is emailed
    2. The Admin opens the Admin area, sees "1 waiting for approval", opens Listings, then
       the listing
    3. Rejects it with a reason; lands on the queue, now empty; the Employer is emailed
    4. The Employer opens the listing from My listings, sees the reason, edits, resubmits
    5. The Admin opens it again, fixes a typo with Edit; the Employer is emailed which
       part changed
    6. Approves it; the Employer is emailed, and My listings shows Live and "1 of 3 open
       listings used"
    7. The Admin finds it under Live, takes it down with a reason; the Employer is
       emailed, sees "Taken down" with the reason, and has "0 of 3" used
  - `posting_journey_test.exs`: its two Admin steps go through the real screens
  - Check the Admin area, the Listings page (queue, empty, another status), the Admin
    view (waiting, live, taken down, hidden region), the two reason forms and the edit
    form at 375 px in a headless browser: no horizontal overflow, buttons 44 px tall
  - Commit: `test(web): moderation journey from submission to take-down (REQ-004-1..10)`

## Phase C — Close

- [ ] **T14** — Docs and coverage
  - `mix jairojobs.spec_coverage 004`: all 56 scenarios have a REQ-named test
  - Spec 000: feature map row and the Listing glossary entry (Admin edit, Taken down is
    final, the two extra kinds of email)
  - `c4-context-system`, `c4-container-system` (moderation emails; every person reads the
    inbox), `usecase-product` ("Approve / reject / edit / take down listing")
  - `data-model.md`, `overview.md`: statuses of `listings` and `Jairojobs.Listings`
  - `README.md`: one paragraph on trying moderation in development (a second account is
    needed to see the emails, since nobody is emailed about their own action)
  - Walk the spec's table of earlier documents row by row and confirm each is done
  - Re-read every diagram in this spec against the built screens and code; reconcile the
    screen flow's example wording (button labels, prompts) with the real screens
  - Commit: `docs(spec 004): architecture and earlier specs brought in line`

- [ ] **T15** — Push; CI green on `main`; set spec, plan and tasks status to `Done`;
  feature map in spec 000 → Done
  - Only when the owner says to push
  - Commit: `docs(spec 004): mark done`

## Definition of Done (constitution §7)

<!-- Walk this at the end and say how each item was met (test counts, CI run, what was checked
     at 375 px). Leave an item unchecked, with the reason, if it cannot be met yet. -->

- [ ] Every REQ in the spec has a passing, REQ-named test
- [ ] Authorization tests present for any private resource
- [ ] `mix precommit` green locally **and** CI green on `main`
- [ ] Works at 375 px width (phone) before desktop
- [ ] No new deps without a justification line in `plan.md`
- [ ] `docs/architecture/` updated if contexts or data model changed
- [ ] Diagrams in this spec and in earlier specs it changed match the built screens and code
- [ ] `tasks.md` checked off; spec status set to `Done`
- [ ] Deployed to Fly.io (once deployment exists) and smoke-checked

## Notes / deviations from plan

<!-- Record anything that changed during implementation and why. -->

- T1: the reason's rules live in `Listing.reason_changeset/1`; `Listings.change_reason/1` is the
  context's name for it, as the plan lists. The three decision changesets take the already
  validated reason as text, not the form's params.
- T1: the status is checked before the reason, so a reject of a listing that is no longer
  waiting answers `:not_pending` even when the reason is also bad.
- T1: 21 tests, all in `listings_moderation_test.exs`. They were run before the code existed
  and failed to compile, as expected; the suite went from 394 to 415.
- T2: `set_listing_status/3` is gone. `listing_in_status_fixture/3` now goes through submit,
  then approve / reject / take down by a throwaway Admin, then close. Three small fixtures
  were added for the tests that set one status directly: `approve_listing_fixture/1`,
  `reject_listing_fixture/2` and `take_down_listing_fixture/2`.
- T2: all 415 tests passed on the first run after the swap, with no test changed beyond the
  five places that called the helper directly, and on five further runs with different
  seeds. The free-tier limit now applies to fixtures as it does to a real Employer; no
  existing test needed more than three open listings for one Employer.
