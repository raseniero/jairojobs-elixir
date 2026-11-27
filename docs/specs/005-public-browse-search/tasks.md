# 005 — Public browse and search — Tasks

**Status:** Done (2026-11-27)
**Plan:** [plan.md](./plan.md) (Approved 2026-11-26)

Rules: ordered, each task is one commit, each task leaves `mix precommit` green.
Commit messages reference REQ IDs; test names follow `REQ-005-n: <scenario>`, with the
scenario's name as the spec writes it (the coverage command ignores capitals).
Scenario-first (constitution §3.12): write the tests listed under a task first, run them to
see them fail, then implement. Mark a finished task `[x]` with `— done YYYY-MM-DD`.

Run `mix precommit` with `set -o pipefail` (or read its output) before each commit: piping
it through `tail` hides a failing exit status. Run `date +%F` before writing any date.

New test files are `async: true`. Each test makes its own regions, so fixed titles such as
"Barista (full-time)" do not clash between tests.

Test files, by the letters the plan uses:
**C** `test/jairojobs/listings_public_test.exs` ·
**L** `test/jairojobs_web/live/listing_live/index_test.exs` ·
**P** `test/jairojobs_web/controllers/listing_controller_test.exs` ·
**S** `test/jairojobs_web/controllers/sitemap_controller_test.exs` ·
**O** `test/jairojobs_web/live/employer/listing_live_test.exs` ·
**A** `test/jairojobs_web/live/admin/listing_live_test.exs` ·
**M** `test/jairojobs/listings_moderation_test.exs`.
A scenario the plan places in two files gets a test of the same name in each, in the task
that builds that side. Controller pages are asserted through `LazyHTML` selectors on the
plan's DOM ids, never by matching raw HTML.

Earlier documents: the spec's table of earlier documents is split across the tasks below
("Docs:"), as the plan's table places them. Every such change gets a changelog row in the
document changed, and every changed `.puml` is rendered on its own
(`plantuml -tsvg file.puml`), not with the render-all script.

## Phase A — Addresses

- [x] **T1** — The slug rule (REQ-005-6) — done 2026-11-26
  - `Jairojobs.Listings.Slug`: `from_title/1` (the region rule, at most 60 characters, cut
    back to a hyphen when the cut falls inside a word, `"job"` when nothing is left) and
    `free/2` (the wanted slug, or the lowest free number from 2, the whole at most 60)
  - Tests (`test/jairojobs/listings/slug_test.exs`, new, unit): "Barista (full-time)" →
    `barista-full-time`; "Café Staff — ₱500/day!!" → `cafe-staff-500-day`; a title of peso
    signs → `job`; a 100-character title cut at a word; one long word cut at 60; `free/2`
    with nothing taken, with the slug taken (`-2`), with `-2` taken too (`-3`), with a gap,
    and with a 60-character slug (the number still fits in 60)
  - Docs: spec 000 feature map, the 005 row → In Progress; spec, plan and this file →
    `In Progress`
  - Commit: `feat(listings): the slug rule for public addresses (REQ-005-6)`

- [x] **T2** — Approval gives a listing its address (REQ-005-6) — done 2026-11-26
  - `mix ecto.gen.migration add_public_addresses`: `listings.slug` (nullable); table
    `listing_addresses` (`listing_id`, `region_id`, `slug`, timestamps; both foreign keys
    refuse a delete); `unique(region_id, slug)`; `unique(listing_id, region_id)`; CHECK
    `listing_addresses_slug_format` (the pattern `regions.slug` has, at most 60)
  - `Jairojobs.Listings.ListingAddress` (schema); `Listing`: field `slug`,
    `approve_changeset` takes it; `slug` is cast by no changeset
  - `approve_listing/3` (still three arguments; the fourth is T14): inside `moderate/3`,
    lock the region row and check it is active (replaces the unlocked read), read the
    slugs taken in the region, `Slug.from_title/1` then `Slug.free/2`, insert the address
    row, write the slug with the status
  - Tests (**C**, new): `REQ-005-6: The address is made at approval`,
    `…: The same title in the same region gets a number`,
    `…: The same title in another region needs no number`,
    `…: A changed title keeps the address` (an Admin edit of the title and of the business
    name; a region rename),
    `…: Unusual characters in a title`,
    `…: An unpublished listing has no public address` (Draft, Pending, Rejected, a
    withdrawn one: no slug, no row),
    `…: An address is never given to another listing` (after a close, and after a take-down);
    a hidden region still refuses approval and writes no address; forged `slug` in the
    Admin edit params is ignored; each unique index and the format CHECK refuse a direct
    bad write
  - Tests (**M**): `approve_listing` as an Employer or a Candidate writes no address
  - Tests (`test/jairojobs/listings_concurrency_test.exs`): two Admins approve the same
    title in one region at the same moment; both succeed, with different slugs. Confirm it
    fails with the region lock removed, then restore the lock
  - Docs: `architecture/data-model.md` (the slug, `listing_addresses`, the Conventions
    line, the table list) and the ERD (the new entity, the planning comment for 005 goes);
    spec 004 REQ-004-5 and `activity-approve-or-reject` (approving also gives the address);
    spec 004 `state-listing` ("Published" gets its public address on approval)
  - Commit: `feat(listings): a listing gets its public address at approval (REQ-005-6)`

- [x] **T4** — A move to another region takes the address along (REQ-005-6) — done 2026-11-26, before T3 (see Notes)
  - `update_listing_as_admin/4`: when the region of a Published listing changes, lock the
    new region's row; take the address the listing already has there, or `Slug.free/2`
    with the slug it has now and insert the row; write `region_id` and `slug` in the same
    update. A Pending listing's move, and an edit that keeps the region, touch no address
  - Tests (**C**): `REQ-005-6: Moving to another region forwards the old address` (the new
    slug, the old row kept, both rows the listing's),
    `…: An earlier address is not given to another listing either`;
    a listing moved back returns to the slug it had there and no row is added; a move into
    a region where its slug is taken gets a number; a move across three regions keeps
    three rows; moving a Pending listing writes nothing
  - Docs: spec 004 REQ-004-8 and `activity-take-down-and-edit` (a move changes the public
    address and the old one forwards; the address is not something an edit can set)
  - Commit: `feat(listings): a moved listing's address follows it (REQ-005-6)`

- [x] **T3** — Addresses for listings already approved; the database checks (REQ-005-6) — done 2026-11-26, after T4
  - `mix ecto.gen.migration give_addresses_to_approved_listings`: data only. Every listing
    with `published_at` and no slug gets one, oldest approval first. The rule is copied
    into the migration; it calls no module of the app. A comment says why
  - `mix ecto.gen.migration add_public_address_checks`: CHECK
    `listings_slug_iff_approved`; `unique(listing_id, region_id, slug)` on
    `listing_addresses` and the foreign key
    `listings(id, region_id, slug)` → `listing_addresses(listing_id, region_id, slug)`
  - `check_constraint/3` and `foreign_key_constraint/3` on the changesets that write a slug
  - Tests (**C**): the CHECK refuses a slug on a Draft and a Published listing without
    one; the foreign key refuses a slug that is not one of the listing's own addresses
  - By hand: run both migrations on the dev database; "Software Engineer" must be at
    `/jobs/davao-city/software-engineer`. Roll back and migrate again once. Write the
    result under Notes
  - Docs: ERD and `data-model.md` (the checks and the foreign key)
  - Commit: `feat(listings): addresses for listings approved earlier, and database checks (REQ-005-6)`

## Phase B — The public reads

- [x] **T5** — Published listings, newest first (REQ-005-1, REQ-005-2) — done 2026-11-26
  - `Listings.list_public_listings/1` on the one private `published/0` query: `:region`,
    `:limit` (20), `:offset`; `{listings, total}`; `published_at` then `id`, descending;
    region preloaded
  - `ListingsFixtures`: one function that sets a listing's `published_at` back (plan
    decision 20). It writes that column and nothing else
  - Tests (**C**): `REQ-005-1: Other statuses are on no public list` (Draft, Pending,
    Rejected, Closed, Taken down; all regions and their own region),
    `…: A hidden region does not hide a listing`,
    `…: The owner's role does not matter`,
    `REQ-005-2: Newest first`,
    `…: A long list is shown in parts` (25: 20 and a total of 25, then 5),
    `…: An edit does not move a listing`; `:region` returns that region's only
  - Commit: `feat(listings): the public list of Published listings (REQ-005-1, REQ-005-2)`

- [x] **T6** — Search and type (REQ-005-4) — done 2026-11-26
  - `list_public_listings/1` gains `:search` and `:type`: Postgres full-text search,
    `simple`, over the title, business name, area and the three texts; words trimmed and
    cut at 100 characters; blank is no search; `total` counts what matched
  - Tests (**C**): `REQ-005-4: Search by a word in the title`,
    `…: Search finds the business and the area`,
    `…: Search finds words in the listing's text` (each of the three texts),
    `…: Every word must be found`, `…: Capitals do not matter`, `…: Filter by type`,
    `…: Search and type together, inside a region`, `…: An empty search is no search`
    (nil, "", spaces); a search never finds a listing that is not Published; words past
    100 characters are cut; punctuation only finds nothing; `%`, `_`, `'` and `\` in the
    words are harmless
  - Commit: `feat(listings): search and type on the public list (REQ-005-4)`

- [x] **T7** — What an address is (REQ-005-6, REQ-005-7, REQ-005-9) — done 2026-11-26
  - `Listings.resolve_public_address/2`: `{:ok, listing}`, `{:moved, %{region_slug,
    slug}}`, `{:gone, %{id, user_id, region}}`, `:not_found`
  - `Listings.list_public_addresses/0`; `Regions.get_region_by_slug!/1`
  - Tests (**C**): the current address of a Published listing; an earlier address gives
    `:moved` with the current one, for a Published and for a Closed listing;
    `REQ-005-7: Nothing of the listing is shown` (`:gone` for Closed and Taken down holds
    only the id, the owner's id and the region); `:not_found` for an unknown slug, an
    unknown region, the listing's id as the slug, and a slug that exists in another
    region; `list_public_addresses/0` holds Published listings only, a hidden region's
    included
  - Tests (`test/jairojobs/regions_test.exs`): `get_region_by_slug!/1` raises for an
    unknown slug and finds a hidden region
  - Commit: `feat(listings): resolve a public address (REQ-005-6, REQ-005-7)`

## Phase C — The lists

- [x] **T8** — The home page is the list (REQ-005-1, REQ-005-2) — done 2026-11-26
  - Router: `live "/", ListingLive.Index, :all` inside the existing
    `live_session :current_user`; `get "/jobs/:region/:listing", ListingController, :show`
    in the same scope, outside the block. `get "/", PageController, :home` goes, with
    `PageController`, `PageHTML` and `home.html.heex`
  - `JairojobsWeb.PublicAddress`: `listing_path/1`, `listing_url/1`
  - `JairojobsWeb.ListingLive.Index`: `#jobs`, the heading for screen readers, the count
    line, the rows as a stream of links (DOM id from the address), the empty message, the
    trust line, the page title. An empty list shows its message and no count line
  - `ListingController.show` for now: a Published listing at its current address renders
    `listing_detail`; everything else is "not found". It exists so a row leads somewhere;
    T12 and T13 finish it
  - Root layout: the title suffix becomes " | jairojobs" (plan decision 10)
  - Tests (**L**, new): `REQ-005-1: A Published listing is public without an account`,
    `…: Other statuses are on no public list`, `…: A taken down listing leaves the lists`,
    `…: A hidden region does not hide a listing`,
    `…: Logging in does not change the lists`,
    `REQ-005-2: Newest first`, `…: What a row shows` (and following the row gives 200),
    `…: How many jobs` (3, and "1 job"), `…: Nothing listed yet` (the message, and no `#jobs-count`),
    `…: A long list is shown in parts` (the first 20; "Show more" itself is T11),
    `…: The trust line is shown`; the title; no listing id anywhere in the page
  - The five tests of `page_controller_test.exs` (REQ-001-1 and the four REQ-001-12 menu
    tests) move to **L** with their names; REQ-001-1 asserts `#jobs`
  - Docs: spec 001 REQ-001-1 and `screenflow-auth` ("Home / Browse jobs" shows rows);
    `architecture/overview.md` (the `:current_user` row gains `/`; the listing address is
    named beside the table as a public controller route)
  - Commit: `feat(browse): the home page lists the jobs (REQ-005-1, REQ-005-2)`

- [x] **T9** — Jobs in one region (REQ-005-3; part of REQ-005-9) — done 2026-11-26
  - Router: `live "/jobs/:region", ListingLive.Index, :region` in the same block.
    `PublicAddress.region_path/2`
  - The region choices (`#region-choices`, `aria-current="page"` on the chosen one), the
    visible heading, rows without the region, "No jobs are listed in Cebu yet." with
    "See all regions", the title "Jobs in Davao City | jairojobs"
  - Tests (**L**): all seven scenarios of REQ-005-3 (`Choose a region`,
    `Rows do not repeat the region`, `The choices are the active regions`,
    `A region with no jobs`, `A hidden region still opens by its address`,
    `Unknown region`, `Back to all regions`);
    `REQ-005-9: A region's jobs have their own title`; a renamed region keeps its address
  - Docs: spec 002 REQ-002-4 (states spec decision 1), `state-region` ("Hidden"),
    `activity-seed-and-consume`; `architecture/overview.md` (`/jobs/:region`)
  - Commit: `feat(browse): jobs in one region (REQ-005-3)`

- [x] **T10** — Search, type and clear (REQ-005-4) — done 2026-11-26
  - The form (`#search-form`): a real GET form the LiveView also handles; `search` and
    `type` in the address; choosing a type applies at once; region choices keep both;
    "Clear search"; "No jobs match your search."; unknown values ignored
  - `config :phoenix, :filter_parameters` gains `"search"`, with its comment line
  - Tests (**L**): `REQ-005-4: Search by a word in the title`, `…: Filter by type`,
    `…: Search and type together, inside a region`, `…: Nothing matches`,
    `…: Clear the search`, `…: A search can be opened again by its address` (a plain
    `get`: the words and the type are filled in), `…: Choosing a region keeps the search`,
    `…: An empty search is no search`; the count follows the search; a searched region
    with nothing found says "No jobs match your search."; an unknown `type` is ignored
  - Tests (`test/jairojobs_web/endpoint_log_test.exs`, "request log"): a real request for
    `/jobs/<region>?search=<an unusual word>`, with the log captured at `:debug` (the
    parameter lines are logged at that level, below the file's usual `:info`); the word is
    nowhere in the log. Make it fail once by taking `"search"` out of the filter
  - Tests (**L**, beside the other filtered-parameter tests): `search` is "[FILTERED]" in
    `Phoenix.Logger.filter_values/1`
  - Docs: spec 001 `screenflow-auth` (the home box gains the search field and the type)
  - Commit: `feat(browse): search and filter by type (REQ-005-4)`

- [x] **T11** — "Show more", and what Back restores (REQ-005-2; plan decision 9) — done 2026-11-26
  - "Show more" (`#show-more`) appends 20 and replaces the address with `shown`, up to
    200; opening an address with `shown` delivers that many rows; past 200 it still
    appends and the address stays
  - Tests (**L**): 45 listings: 20, then 40, then 45 and no button; a plain `get` with
    `shown=40` delivers 40 rows; `shown=40` with a search; `shown` of 0, 30, "abc" and
    100000 are handled; the button is absent at 20 or fewer
  - Commit: `feat(browse): show more, kept in the address (REQ-005-2)`

## Phase D — The listing page

- [x] **T12** — The listing's public page (REQ-005-5; part of REQ-005-1 and REQ-005-8) — done 2026-11-26
  - `ListingHTML` `show`: "← Jobs in Davao City", `listing_detail` with its new `trust`
    slot and the title as the page's `h1`, the "coming soon" line, the page title
  - `ListingComponents.listing_detail/1`: the `trust` slot and the heading level. The
    owner view and the Admin view must look as before
  - Tests (**P**, new): all eight scenarios of REQ-005-5 (`Read a listing without an
    account`, `The trust line`, `An older listing shows the date`, `Optional parts are
    left out`, `The public sees the listing as it is now`, `What is never shown`,
    `Applying is not possible yet`, `Back to the region's jobs`);
    `REQ-005-1: A Published listing is public without an account`;
    `REQ-005-8: A shared link opens without an account`;
    `REQ-005-6: A changed title keeps the address` (the page shows the new title);
    a listing in a hidden region opens; no accent button on the page
  - Docs: spec 001 `screenflow-auth` (the "Listing detail" box: the "coming soon" line,
    not "Apply for this job")
  - Commit: `feat(browse): the listing's public page (REQ-005-5)`

- [x] **T13** — No longer listed, forwarding, not found (REQ-005-7; rest of REQ-005-6) — done 2026-11-26
  - `ListingController.show` answers by `resolve_public_address/2`: 301 for `:moved`, 410
    with `ListingHTML` `gone` for `:gone` (`#listing-gone`, "See jobs in Davao City"),
    404 otherwise. `get "/jobs"` forwards to `/` (plan decision 15)
  - Tests (**P**): all six scenarios of REQ-005-7 (`A closed listing's address says so`,
    `A taken down listing's address says the same`, `Nothing of the listing is shown`,
    `The page is answered as gone`, `The owner and Admins see the same page`,
    `An address that never was a listing`);
    `REQ-005-6: The id is never a public address`,
    `…: Moving to another region forwards the old address` (301, to the current address,
    parameters dropped),
    `…: An earlier address is not given to another listing either` (the old address still
    forwards to the moved listing); the old address of a listing that was moved and then
    closed forwards to the page that says "no longer listed"; `/jobs` forwards to `/`;
    an unknown region with any slug is 404
  - Docs: spec 001 `activity-request-access` (its list of public pages); spec 003
    lifecycle table and `state-listing` (wording checked against REQ-005-1 and -7), REQ-003-9
    and `activity-after-submitting`; spec 004 REQ-004-3 and REQ-004-7 ("until the public
    pages exist" points here), `activity-take-down-and-edit` ("No longer public (005)")
  - Commit: `feat(browse): a listing that is no longer listed says so; earlier addresses forward (REQ-005-6, REQ-005-7)`

## Phase E — Links, the email, sharing, search engines

- [x] **T14** — Links between a public page and the pages that manage it (REQ-005-10) — done 2026-11-26
  - Owner view and Admin view: "See the public page" (`#see-public-page`) while Published
  - Public page and gone page: `#manage-links` last on the page: "This is your listing."
    and "Manage this listing" for an owner who may still post; "Open the Admin view" for
    an Admin
  - Tests (**O**): `REQ-005-10: The owner view links to the public page`,
    `…: Only a Published listing has the link`
  - Tests (**A**): `REQ-005-10: The Admin view links to the public page`,
    `…: Only a Published listing has the link`
  - Tests (**P**): `…: An Admin gets to the Admin view from the public page`,
    `…: The owner gets to their listing from the public page`,
    `…: Nobody else sees those links` (Visitor, Candidate, another Employer),
    `…: The same links on a listing that is no longer listed`; an Admin who owns it sees
    both; an owner demoted to Candidate sees neither
  - Docs: spec 003 REQ-003-10, `activity-my-listings`, `screenflow-posting`,
    `wireframe-posting`; spec 004 REQ-004-4, `activity-find-and-review`,
    `screenflow-moderation`
  - Commit: `feat(browse): links between a listing's public page and its owner and Admin views (REQ-005-10)`

- [x] **T15** — The approval email links to the public page (REQ-005-10; amends REQ-004-9) — done 2026-11-26
  - `approve_listing/4` (`public_url`); `ListingNotifier.deliver_approved/4`: the public
    link first, then My listings; the Admin view passes `PublicAddress.listing_url/1`
  - Every caller: the Admin view, `ListingsFixtures`, the tests, and by hand
    `priv/phone_check/003.exs` and `004.exs`, which the compiler does not see. Run
    `scripts/phone-check.sh 004` once to prove the scripts still work
  - Tests (**M**): `REQ-005-10: The approval email links to the public page` (both links,
    the public one first); the existing REQ-004-9 approval-email test gains the public
    link, name unchanged; an Admin approving their own listing still sends nothing
  - Docs: spec 004 REQ-004-9, `activity-emails`, `sequence-decision-email` (the four
    changes the plan lists), `screenflow-moderation`
  - Commit: `feat(listings): the approval email carries the public link (REQ-005-10, REQ-004-9)`

- [x] **T16** — Share, and the preview (REQ-005-8) — done 2026-11-27
  - "Share" (`#share-listing`, a plain button, `data-share-title`, `data-share-url`),
    `#share-status` (`aria-live="polite"`), the colocated hook `.Share`: share sheet, else
    copy and "Link copied", else write the address out
  - `JairojobsWeb.Seo` and the root layout: `og:title`, `og:description`, `og:url`,
    `og:type`, `og:site_name` on the listing page
  - Tests (**P**): `REQ-005-8: The page offers Share` (the title and the full address),
    `…: A shared link has a preview`; nothing is added to the shared address
  - The tap is checked by hand in T19
  - Docs: spec 001 `screenflow-auth` (the "Listing detail" box gains "Share")
  - Commit: `feat(browse): share a listing (REQ-005-8)`

- [x] **T17** — What search engines read on each page (REQ-005-9) — done 2026-11-27
  - `Seo`: description and `rel="canonical"` for the home page, a region's list and a
    listing; `noindex` for a list with words or a type, a hidden region's list and the
    gone page; the `JobPosting` block, HTML-safe JSON
  - Tests (**P**): `REQ-005-9: A listing page has its own title and description`,
    `…: A listing page carries job details a search engine can read` (parsed as JSON:
    title, business, area and region, PHP per month, type, date posted, text; no closing
    date, no id),
    `…: A hidden region's list asks not to be listed` (the listing's page does not),
    `…: A page is complete as first delivered`; a `</script>` in an employer's text does
    not end the block; the gone page asks not to be listed
  - Tests (**L**, plain `get`): `…: Search results ask not to be listed` (words; a type),
    `…: A hidden region's list asks not to be listed`,
    `…: A page is complete as first delivered`; the stated address of a list has no
    parameters; an unnarrowed list of an active region does not ask
  - Commit: `feat(browse): titles, descriptions and job details for search engines (REQ-005-9)`

- [x] **T18** — The sitemap (REQ-005-9) — done 2026-11-27
  - `get "/sitemap.xml", SitemapController, :index` in a scope with no pipeline;
    `priv/static/robots.txt` names `https://jairojobs.com/sitemap.xml`
  - Tests (**S**, new): `REQ-005-9: The sitemap lists the public pages only` (the home
    page, the active region, the Published listing; not the hidden region's list, the
    Closed listing or the Draft); a Published listing in a hidden region is listed; the
    answer is XML and sets no session cookie
  - Docs: `c4-context-system`, `c4-container-system` (a search engine and a chat app read
    the public pages and the sitemap; the Visitor's "Browses, searches" is true);
    `architecture/overview.md` (the sitemap route)
  - Commit: `feat(browse): sitemap of the public pages (REQ-005-9)`

## Phase F — Close

- [x] **T19** — One journey, coverage, phone checks, documents — done 2026-11-27 (two items left for the owner: see Notes)
  - `test/jairojobs_web/live/browse_journey_test.exs`: an Employer posts, an Admin
    approves, a visitor finds the listing on the home page, by region and by search, and
    opens it; the Admin moves it and the old address forwards; the Employer closes it and
    its address says it is no longer listed
  - `mix jairojobs.spec_coverage 005`: all 74 scenarios covered
  - `priv/phone_check/005.exs` (the pages the plan lists); run
    `scripts/phone-check.sh 005`, and `003` and `004` again; look at the screenshots
  - By hand, on a phone or a phone-sized browser: tap "Share" where there is a share
    sheet and where there is none. Write what happened under Notes
  - Re-read all five diagrams of this spec against the built screens and code; fix what
    drifted
  - Walk the spec's table of earlier documents row by row and write under Notes which
    task did each; `architecture/overview.md`: the Listings row says the public pages are
    implemented
  - Walk the Definition of Done below and say how each item was met
  - Commit: `test(browse): journey from posting to "no longer listed"; spec 005 closing checks`

- [x] **T20** — Push (on the owner's word); CI green on `main`; spec, plan and tasks →
  `Done`; spec 000 feature map → Done — done 2026-11-27

## Definition of Done (constitution §7)

Walked on 2026-11-27, at the end of T19.

- [x] Every REQ in the spec has a passing, REQ-named test — `mix jairojobs.spec_coverage
  005`: "All 74 scenarios have a REQ-named test." 782 tests pass; 230 of them were written
  for this spec.
- [x] Authorization tests present for any private resource — the public pages hold no
  private resource; what they must never show is tested instead: a listing in each other
  status is on no list, in no search, in no sitemap and has no page (context, lists,
  listing page, sitemap); the owner's and the Admin's links are shown to nobody else; a
  listing's id opens nothing public.
- [x] `mix precommit` green locally **and** CI green on `main` — green locally (782
  tests). CI: run 46064859189 on commit `3c7de0f`, success, 2026-11-27.
- [x] Works at 375 px width (phone) before desktop — `scripts/phone-check.sh 005`: 21
  pages, 0 failed; I looked at four of the screenshots. `003` (13 pages) and `004` (15
  pages) were run in T15, after the last change to their screens: 0 failed. One point is
  put to the owner: how many rows fit on the first screen (Notes, T19).
- [x] No new deps without a justification line in `plan.md` — no dependency was added.
- [x] `docs/architecture/` updated if contexts or data model changed — the overview, the
  data model, the ERD and both C4 diagrams.
- [x] Diagrams in this spec and in earlier specs it changed match the built screens and
  code — all five of this spec's diagrams were read again against the screens; four
  changed (Notes, T19). The 21 rows of earlier documents are walked below.
- [x] `tasks.md` checked off; spec status set to `Done` — 2026-11-27, after CI passed.
  One check is outstanding by the owner's decision: "Share" on a real phone, after
  deployment (`TODO.md`).
- [ ] Deployed to Fly.io (once deployment exists) and smoke-checked — no deployment
  exists yet (parked).

## Notes / deviations from plan

- Written 2026-11-26. The plan's 13 build steps became 20 tasks. Two things differ from
  the plan's order, neither in what is built:
  - T8 gives the listing's address a first, bare page (a Published listing only), so that
    a row on the home page leads somewhere and "the whole row opens the listing's public
    page" can be tested in the task that builds the row. T12 and T13 finish that page.
    The plan had the listing page entirely in step 8.
  - The preview tags (`og:`) arrive with Share in T16, and the other head tags in T17. The
    plan had the preview in step 11 and the rest in step 12; `Seo` is therefore created in
    T16.
- 2026-11-26, after a comparison of the spec, its diagrams, the plan and this file (the
  owner approved the changes): T8 says an empty list has no count line; T10 has two tests
  that searched words are not logged, one on a real request in `endpoint_log_test.exs`
  and one on the parameter filter. The plan was amended the same day to say the same, so
  this is no longer a difference from it.
- Left for T19, when every diagram is re-read against what was built: the Share diagram
  draws two outcomes and the plan has a third (the address written out, plan decision
  19); the screen flow does not draw `/jobs` forwarding to `/` (plan decision 15).
- T1: 16 unit tests. `Slug.free/2` takes any list or set of taken slugs. The cut works on
  the slug, not the title, so "at a word" means "at a hyphen". Spec 000's changelog does
  not list feature-map status changes, so the 005 row changed without a changelog row.
- T2: the region's row is locked with `FOR NO KEY UPDATE`, not the plan's `FOR UPDATE`. Both
  make approvals in one region take turns and hold off a hide or a rename. `FOR UPDATE`
  would also make an Employer who is saving a listing in that region wait, because the
  database checks the listing's region with a lock that `FOR UPDATE` blocks; the weaker
  lock does not.
- T2: `listing_addresses.listing_id` refuses a delete with `on_delete: :nothing`, not
  `:restrict`. Both refuse; `:nothing` checks at the end of the statement, which T3's
  foreign key in the other direction will need for a clean-up to be possible at all.
- T2: the concurrency test runs 25 rounds of two approvals. With the lock taken out it
  failed (the second approval crashed on the unique index); with it, it passes. Its
  clean-up, and the phone check's (`priv/phone_check/support.exs`), now remove a listing's
  addresses before the listing. The phone check's change was not run; T15 runs it.
- T2: 18 new tests: 16 in the new context file, 1 in the moderation file, 1 concurrency
  test. Three of them try to break the database's rules with a direct write, and a fourth
  shows a listing with an address cannot be deleted.
- T2: looked at all three re-rendered diagrams (the ERD, `activity-approve-or-reject`,
  spec 004's `state-listing`). `data-model.md` and the ERD say "through spec 005's first
  migration"; T3 adds the checks.
- T4 was done before T3, and they are listed in that order now. T3's foreign key says a
  listing's current address must be one of its own recorded addresses. Spec 004's tests
  already move a Published listing to another region, and until the address moved with it
  (T4) the foreign key refused those saves: two of spec 004's tests failed. The plan had
  the checks first (step 2) and the move after (step 3); that order cannot be built. The
  plan's review missed it. Nothing else about either task changed.
- T4: 10 tests. A move locks the new region's row, as an approval does, so two moves, or
  a move and an approval, cannot pick the same slug. A move into a hidden region was
  already refused; it now also writes no address. The "edited" email still names "Region"
  and says nothing of the address.
- T3, by hand on the dev database: "Software Engineer" is at
  `/jobs/davao-city/software-engineer`, with one row in `listing_addresses`; its
  `updated_at` did not change. Rolled back both migrations and migrated again: the same
  address, still one row.
- T3, on a throwaway copy of the dev database (created, checked, dropped): eight
  listings approved "earlier", made by copying the one Published row. Three with the same
  title in Davao got `software-engineer`, `-2`, `-3` in order of approval, the third one
  Closed; a Taken down "Café Staff — ₱500/day!!" got `cafe-staff-500-day`; two titles of
  peso signs got `job` and `job-2`; an 83-character title was cut at a word to 58
  characters; the same title in Cebu needed no number; the Pending listing got nothing.
  Rolling back and migrating again there left eight addresses, and both checks in place.
- T3: 3 new tests on what the database refuses (a slug on a listing never approved, an
  approved listing without one, a slug or a region that is not one of the listing's own
  addresses, removing a current address). One of spec 004's tests wrote
  `published_at` directly to show the database accepts it; it now records an address
  first, since an approved listing must have one.
- T3: a listing and its addresses refer to each other, so neither deletes alone. The
  concurrency test's clean-up and the phone check's remove both in one statement.
  `scripts/phone-check.sh 004` was run to prove it: 15 pages, 0 failed, "removed 6
  listings, 2 regions, 3 users", dev database unchanged. So the phone-check change T2
  left unrun has now been run. I did not look at its screenshots; no screen changed.
- T3: the migration that gives the addresses has no automated test. It was checked by
  the two runs above.
- T5: 10 tests. With the rule weakened on purpose to "was ever approved", the test for
  the other statuses failed (it found the Closed and the Taken down listing); restored.
  The test helper that sets a listing's approval time back is
  `ListingsFixtures.approved_ago/3` (plan decision 20). Two listings approved at the same
  instant are ordered by id, later first, so the order is always the same.
- T6: 21 tests. `Listings.search_words/1` is the one place that trims the words and cuts
  them at 100 characters; the screens will use it too, so the field and the address show
  exactly what was looked for. It also turns control characters into spaces: the database
  refuses a null byte, and a pasted one would otherwise be an error page.
- T6: with the search switched on purpose to Postgres's English rules, one test failed:
  "driver" found "drivers". Restored to `simple`.
- T6: the fixtures' usual "About the job" mentions a barista, so the search tests give
  their listings a text that names nothing they search for.
- T6: one test pins what the plan chose and the spec does not promise: "driver" does not
  find "Delivery drivers wanted". If search is ever made more forgiving, that test changes.
- T7: 14 tests (11 in the context file, 3 for regions). With the lookup changed on
  purpose to read any listing, not only a Published one, two tests failed (a Closed
  listing came back as if it were public); restored.
- T7: text that could never be a slug is "not found" without asking the database: capital
  letters, spaces, a null byte, a listing's id. `Region.slug?/1` is the one test of the
  shape, used for a region's slug and a listing's. `Regions.get_region_by_slug/1` (spec
  002) uses it too: before, a null byte in a region's address would have been an error
  page, not "not found". Its answers for every real slug are unchanged.
- T7: `:moved` is answered for an earlier address whatever the listing's status, so the
  old address of a listing that was moved and then closed forwards to the address that
  says "no longer listed", as `activity-open-a-listing` draws it.
- T8: 22 tests in the new file, 5 of them the home-page tests of spec 001, moved with
  their names. The suite went from 644 to 661.
- T8: a row's DOM id is `job-<region slug>--<listing slug>`, with a double hyphen between
  the two slugs, not the single one in the plan's table. With one hyphen, the region
  "davao" with the slug "city-barista" and the region "davao-city" with the slug "barista"
  would make the same id. No slug contains a double hyphen, so now none can clash.
- T8: an address that is not the current address of a Published listing answers 404 with
  the usual "Not Found" page, through the router's own "no such address" error. T13 gives
  an earlier address and a closed listing their own answers.
- T8: looked at the home page and the bare listing page at 375 px in a headless browser,
  with the dev database's one Published listing: no sideways scrolling, nothing in the
  page under 44 px, titles as specified. "✓ Approved" is green text in a thin green
  outline on white, not a filled pill: the design guide's colours are checked for
  contrast on white.
- T8: the stream of rows is left out of the page when the list is empty, so an empty
  list shows no stray divider lines.
- T8: `screenflow-auth` (spec 001) still says "region chips" on the home page, which T9
  builds. The image was re-rendered; I looked at it.
- T9: 12 tests. Choosing a region is a patch of the same LiveView; every choice is also a
  real link, so it works in what is first delivered. The path of a list is built by
  `PublicAddress.list_path/1` (the task called it `region_path/2`).
- T9: "See all regions" under an empty region's list is a link of its own, 44 px tall. As
  first written it sat inside the sentence and measured 18 px in the browser.
- T9: looked at the home page, a region with a job and an empty region at 375 px. No
  sideways scrolling of the page; nothing under 44 px after the fix above.
- T9, for the owner: with the dev database's four regions the row of choices is wider
  than a phone, as the mock expects, and scrolls inside itself. On the home page the
  chosen one, "All regions", is last and so starts off the screen: the visitor sees four
  unchosen regions and has to scroll the row to find it. Built as the spec and the plan
  say (alphabetical, then "All regions"; one row). Put to the owner, not changed.
- T9: spec 002's `activity-seed-and-consume` was read against REQ-005-3 and agrees
  (active regions A to Z; a region found by its slug even when hidden; otherwise not
  found), so it did not change. `state-region` was re-rendered; I looked at it.
- T9, the owner's answer (2026-11-26): "All regions" goes first. Spec decision 26;
  REQ-005-3's rule and one scenario amended, with `screenflow-browse` and
  `activity-browse-and-search`, in the commit that changed the screen. The plan's line on
  the region choices says the same now. Four tests changed what they expect. Here the
  code was changed a moment before the tests, not after: the old tests failed against the
  new order, which at least shows they watch it.
  The design guide's mock still draws "All regions" last; its note does not mention it.
- T10: 19 tests: 18 for the screen and one that follows a real search through the log.
- T10, found by that test: with the log at its most detailed level, the searched words
  were in it. Not in the parameter lines, which the filter covers, but in the database's
  query lines: at that level Ecto writes every query with the values given to it. The two
  queries of a search are now not logged at all (`log: false`), only when words are
  searched. With "search" taken out of the filter on purpose, both log tests failed;
  restored.
- T10, for the owner to know: the same is true of every other query. At the most
  detailed level, which the dev server uses, Ecto's query lines carry whatever the query
  was given: an email address at log-in, a listing's text when it is saved. Production
  logs at `info`, where those lines are not written, and the existing tests of the log
  run at `info`. Nothing was changed about that; it is older than this spec.
- T10, in a real browser (headless Chromium, the dev server): with scripts switched off,
  Search, the type, "No jobs match your search." and "Clear search" all work as plain
  page loads, which the plan had only reasoned. With scripts on: searching and choosing a
  type change the address without a reload, Back steps to the previous search with its
  rows and its field, and the page title follows the region. The dev server's own log,
  at its most detailed level, did not contain the searched word.
- T10: on a region's list the heading sits between the region choices and the search
  form. The form is two lines (field and Search; type), so on a phone the first row of
  jobs starts about half-way down the first screen. Not changed; to look at in T19's
  phone check, against "about six rows to a phone screen".
- T10: a region's choice that is far along the row can start off the screen on its own
  list, as "All regions" did on the home page. With four regions the fourth is half
  visible. Nothing scrolls the row to the chosen one; that would need a script.
- T10: when no type is chosen the select shows "Any type" because it is the first
  option; no option is marked selected.
- T11: 7 new tests, and "REQ-005-2: A long list is shown in parts" now also asks for more.
  One test builds 225 listings to go past the 200 rows the address keeps; the file takes
  about 2.5 seconds.
- T11: up to 200 rows "Show more" is a real link to the same list opened 20 rows further,
  marked to replace the address; past 200 it is a button that adds rows where they are.
  When only `shown` grows, only the new rows are fetched and they go under the ones
  already there. A new search, type or region starts again at 20. A `shown` that is not a
  step of 20 goes down to one; nonsense is 20; anything above 200 is 200.
- T11: the test configuration sorts an address's parameters by name, so tests see
  `?search=…&shown=…&type=…`; the app writes `search`, `type`, `shown`.
- T11, in a real browser (headless Chromium, the dev server, 45 throwaway listings, since
  removed; the dev database's counts are what they were): 20 rows, then 40, then all 46,
  with the browser's history the same length throughout. Scrolled to row 42, opened it,
  pressed Back: the address was `/?shown=60`, all 46 rows were there, and the page was at
  the same place, with that row in view. A fresh visit to a list starts at the top.
  Reloading keeps the place. One more Back leaves the list in a single step.
- T11, what puts the visitor back at the same place: LiveView, not the browser by
  itself. LiveView switches the browser's own return-to-place off, notes the place in
  the history entry a tenth of a second after scrolling stops, and puts it back on every
  page load. So the plan's sentence holds in effect. I first thought it did not: my
  script clicked a row before the place had been noted, and the page came back at the
  top. I wrote a small hook to restore the place, then checked that the page failed
  without it. It did not fail, so the hook was not needed and is not in the commit. A
  visitor who taps a row within a tenth of a second of the page stopping comes back to
  the place noted before that.
- T12: 18 tests in the new file for the listing page. Nine of them already passed against
  the bare page from T8 (the facts and the texts come from `listing_detail`); the other
  nine failed first.
- T12: on the public page the title is the page's `h1` and the sections are `h2`; in the
  owner's and the Admin's views they stay `h2` and `h3`. One test opens both of those
  views and checks they are as they were, with no trust line.
- T12: the page title is set here ("Barista (full-time) — Kape Isla, Davao City |
  jairojobs"); T17 adds the description and the rest of the head.
- T12: looked at the page at 375 px with the dev database's listing: no sideways
  scrolling, nothing under 44 px. It reads as the mock does, without the Apply bar.
- T12: spec 001's `screenflow-auth` had an arrow from the listing page's Apply button to
  Log in. There is no such button until spec 007, so the arrow is gone, with a comment in
  the source saying it returns then. No user story of spec 001 used that path. I looked
  at the re-rendered image.
- T13: 14 tests (six scenarios of REQ-005-7, three of REQ-005-6, five more). The one
  from T8 that stood in for them, in the lists' test file, is gone.
- T13: the "no longer listed" page is given the region and nothing else, so it has
  nothing of the listing to show. Its title is "This job is no longer listed |
  jairojobs" and its one sentence is the page's heading. A test compares the page of a
  Taken down listing with that of a Closed one, word for word.
- T13: with the dev server, by `curl`: `/jobs` and `/jobs?search=x` answer 301 to `/`;
  the dev database's listing answers 200; an unknown slug and an unknown region 404. The
  "no longer listed" page was not looked at in a browser here (the dev database has no
  closed listing); T19's phone check does that.
- T13: spec 003's `state-listing` was read against REQ-005-1 and REQ-005-7 and did not
  change. The three diagrams that did change (`activity-request-access`,
  `activity-after-submitting`, `activity-take-down-and-edit`) were re-rendered; I looked
  at all three.
- T14: 14 tests: 3 for the owner view, 3 for the Admin view, 8 for the public page and
  the "no longer listed" page. Seven of REQ-005-10's eight scenarios are covered; the
  eighth, the email, is T15.
- T14: on the public page the box is last, with "This is your listing." above the
  owner's link. On the "no longer listed" page the same links appear without that
  sentence, as the screen flow draws it. An owner demoted to Candidate gets neither.
- T14: the paths of the two links are worked out in the controller and passed to the
  page, so the "no longer listed" page still receives nothing of the listing but its
  region and those paths.
- T14, in a real browser at 375 px (throwaway data, removed; the dev database's counts
  are what they were), eleven pages: the public page and the "no longer listed" page as
  a visitor, as the owner and as an Admin; the public page of an Admin's own listing;
  the owner view; the Admin view. Each showed exactly the links it should and no others,
  none scrolled sideways, nothing was under 44 px. "See the public page" led from the
  owner view to the public page, and "Manage this listing" and "Open the Admin view" led
  back. I looked at three of the screenshots. This is also the first look at the "no
  longer listed" page, which T13 could not show.
- T14: five diagrams of specs 003 and 004 were re-rendered. I looked at
  `screenflow-posting` and `screenflow-moderation`; the other three changed by one line.
- T15: 3 new tests, and the existing "REQ-004-9: approved email" also expects the public
  link. One of the new ones approves on the Admin's screen and checks the email carries
  the address the site really builds, and that the address opens.
- T15: `approve_listing/4` had 33 callers by now, not the 25 counted for the plan: the
  tests written since added eight. One in the app, one fixture, 29 in tests, and the two
  phone-check scripts. The compiler found the 31; the two scripts were changed by hand.
- T15: both phone-check scripts were run to prove they still work: `004`, 15 pages, 0
  failed; `003`, 13 pages, 0 failed; the dev database unchanged after each. Their pages
  include the owner view and the Admin view of a Published listing, which now carry "See
  the public page", so the 44 px check has passed on that link in both. I did not look at
  these screenshots again.
- T15: the three other emails to the owner still take one address and carry one link; a
  test checks none of them mentions `/jobs/`.
- T15: `sequence-decision-email` changed in four places, as the plan lists, with the
  address step drawn as optional ("approve, or an edit that moves a Published
  listing", since T4's move takes the same step). I looked at the re-rendered sequence
  diagram and at `activity-emails`; not at `screenflow-moderation`, where one line
  changed in a diagram looked at in T14.
- T16: 6 tests. All three scenarios of REQ-005-8 are covered now ("A shared link opens
  without an account" since T12).
- T16: the share sheet is given the listing's title ("Barista (full-time)") and its
  address. The preview's title is longer, "Barista (full-time) — Kape Isla", as the spec
  writes it.
- T16: `JairojobsWeb.Seo` builds what goes in the head and `Layouts.seo/1` writes it, in
  the root layout. A page that assigns nothing gets no tags: the "no longer listed" page
  has no preview of the listing, and a test says so.
- T16, what a tap does, in a real browser (headless Chromium, the dev server, the dev
  database's listing). The spec asks for this by hand on a phone; this is the nearest I
  can get, and a tap on a real phone is still to be done (T19):
  - no share sheet, which is what a desktop browser has: the address was copied, read
    back from the clipboard as `http://localhost:4010/jobs/davao-city/software-engineer`,
    and the page said "Link copied";
  - a share sheet (a stand-in that records what it is given): it was given the title and
    that address, and the page said nothing;
  - the sheet closed again: nothing said, nothing copied;
  - the sheet failing for another reason: the address was copied, "Link copied";
  - neither possible: the address was written out beside the button, and the page did
    not become wider than the phone;
  - scripts switched off: the button does nothing and nothing breaks.
- T16: the plan's claim that a hook runs on a page with no LiveView, and that no live
  connection is opened for it, was read in LiveView's source before. Now seen: the hook
  ran on the listing page, and the browser opened no live connection there.
- T16: this is the project's first hand-written JavaScript: 25 lines, colocated with the
  component that needs it (`ListingHTML.share/1`). The fallback when a share
  sheet fails for a reason other than being closed (copy the address) is not in the
  plan; the plan has share, else copy, else write out.
- T16: `screenflow-auth` (spec 001) gained "[ Share ]". Not looked at again: one line in
  a diagram looked at in T12.
- T17: 17 tests: 10 for the listing page, 7 for the lists. Six of REQ-005-9's seven
  scenarios are covered; the seventh, the sitemap, is T18.
- T17: the job details are one `JobPosting` block in the head, built from a map and
  written as JSON in which `<`, `>` and `&` are escapes. A test gives a listing texts
  with `</script>`, an `<img onerror>`, an unclosed comment and `]]>`: the page still has
  exactly one block, it still parses, and none of it reaches the page as markup. With the
  escaping taken out on purpose that test failed; restored.
- T17: the block's description is the three texts as simple HTML, which is how search
  engines read a job's description: each text escaped, its line breaks as `<br>`,
  "Requirements" and "Benefits" as headings in bold. The date posted is the day of
  approval in Manila. There is no closing date and no identifier.
- T17: the types of work are named as schema.org names them: FULL_TIME, PART_TIME,
  CONTRACTOR, TEMPORARY, INTERN.
- T17: a list opened further (`shown` alone) narrows nothing, so it does not ask not to
  be listed; it states the list's plain address, so it is not counted twice. An empty
  search and a type the site does not have are the same.
- T17, on the dev server, by reading what five addresses deliver (the listing, the home
  page, a region, a searched region, `?shown=40`): each has the title, description, one
  address and "do not list" the plan's table gives it, and the listing's block parsed
  as JSON with the right values.
- T17: a page's one address and the address in the preview are built from the address
  the site is configured to answer at. On the dev machine that is `localhost`; in
  production it must be `jairojobs.com`, which is part of the deployment that is parked.
- T17: when a visitor changes a list without a reload only the title follows; the
  description and the rest stay as first delivered. As the plan says, that is enough:
  search engines and chat apps read the first delivery of each address.
- T17: not checked: the block has not been put through a search engine's own checker
  (Google's Rich Results Test needs a page it can reach, or pasted code, in a browser).
- T18: 11 tests. All seven scenarios of REQ-005-9 are covered now, and with them all 74
  scenarios of the spec should have a test; T19 runs the coverage command to say so.
- T18: a listing's entry carries the day it last changed (`updated_at`); the lists carry
  no date. One test asks for every address the sitemap lists and checks each opens.
- T18, on the dev server: the sitemap answered as `application/xml`, with no cookie,
  parsed as XML, and listed six addresses: the home page, the four regions' lists, and
  the one listing with its date. `robots.txt` ends with the line naming the sitemap.
- T18: `robots.txt` names the production address, `https://jairojobs.com/sitemap.xml`
  (plan decision 12), also when the site runs elsewhere, as on the dev machine.
- T18: both C4 diagrams were re-rendered with a search engine and a chat app as outside
  readers; I looked at both. The overview has a paragraph on them and names the
  sitemap's route.
- T19: the journey test follows one listing through 10 steps on the real screens of an
  Employer, an Admin and a visitor: posted, approved (the email carries the public
  address), found on the home page, by region and by search, opened, reached by its owner
  and by the Admin from its public page, moved to another region (the old address
  forwards), closed (off every list and the sitemap; its address says "no longer listed"),
  and its two addresses never given to a new listing. It passed the first time it ran;
  nothing in the app changed for it.
- T19: `mix jairojobs.spec_coverage 005`: all 74 scenarios have a REQ-named test.
- T19: `priv/phone_check/005.exs` lists 21 pages: 14 as a visitor (both lists, a list
  opened to 40 rows, an empty region, a hidden region, a search, a search that finds
  nothing, a search typed into the form, four listing pages including one with a
  90-character title and a long business name and one with only the required parts, the
  page after "Share" is tapped, "no longer listed"), 3 as the owner, 4 as an Admin.
  `scripts/phone-check.sh 005`: 21 checked, 0 failed, dev database unchanged. I looked at
  four screenshots: the home page, the long listing (top and bottom), and the hidden
  region's list.
- T19, for the owner, rows on the first screen. The spec asks for "about six rows to a
  phone screen". With the region choices, the search row and the type row above the
  list, the first row starts about 300 px down. A row is about 98 px when nothing wraps.
  On a screen 800 px tall that is five rows; on 667 px (a small iPhone), under four. The
  mock reaches six because it has no search field or type choice. Not changed. Ways to
  gain room: put the type choice beside the count line (about half a row), or tighten
  the spacing of the form (a little).
- T19, for the owner, "Share" on a real phone. REQ-005-8 asks for the tap to be checked
  by hand on a phone. Not done: I have no phone. What was done is in the T16 note (six
  cases in a headless browser). Still to do on a phone: tap "Share" on a listing and see
  the phone's share sheet open with the title and the address.
- T19: all five diagrams of this spec were read again against the built screens. Four
  changed: `activity-share-and-be-found` (a third outcome of Share: the address written
  out), `activity-browse-and-search` (the address keeps how far the list is opened),
  `activity-open-a-listing` (the way back is first on the page, as built),
  `screenflow-browse` (a region's heading; "Clear search" whenever words or a type are
  set; the third outcome of Share; `/jobs`). `activity-address-and-links` agreed. I looked
  at all five re-rendered images.
- T19: three things the plan decided (decisions 9, 15 and 19) and the app does were not
  in the spec's requirements, so the diagrams above would have shown more than the text.
  Each is now one rule in the spec, with a changelog row: how far a list is opened is in
  its address (REQ-005-4), `/jobs` forwards to the home page (REQ-005-3), the third
  outcome of Share (REQ-005-8). No scenario changed. The spec's review section names the
  commit.
- T19: the plan was not edited at the close. Where it differs from what was built, the
  notes above say so task by task: the order of T3 and T4, the lock on the region's row,
  the double hyphen in a row's id, "All regions" first, two log tests, the hook that was
  not needed, 33 callers of `approve_listing`, the extra fallback of Share.
- T19, the spec's table of earlier documents, row by row:
  1. 000 feature map: In Progress since T1; Done at T20.
  2. 001 REQ-001-1 and `screenflow-auth`: T8 (the home page), T10 (search and type), T12
     (the listing page), T16 (Share).
  3. 001 `activity-request-access`: T13.
  4. 002 REQ-002-4: T9.
  5. 002 `state-region`: T9.
  6. 002 `activity-seed-and-consume`: read in T9; agrees; not changed.
  7. 003 lifecycle table, `state-listing`: a sentence under the table in T13;
     `state-listing` read in T13, agrees, not changed.
  8. 003 REQ-003-9 and `activity-after-submitting`: T13.
  9. 003 REQ-003-10, `activity-my-listings`, `screenflow-posting`, `wireframe-posting`: T14.
  10. 004 REQ-004-9, `activity-emails`, `sequence-decision-email`, `screenflow-moderation`: T15.
  11. 004 REQ-004-4, `activity-find-and-review`, `screenflow-moderation`: T14.
  12. 004 REQ-004-3 and REQ-004-7: T13.
  13. 004 REQ-004-5 and `activity-approve-or-reject`: T2.
  14. 004 REQ-004-8 and `activity-take-down-and-edit`: T4 (the move), T13 ("no longer
      public").
  15. 004 `state-listing`: T2.
  16. `architecture/overview.md`: T8, T9 and T18 (the routes), this task (the Listings
      row says implemented).
  17. `architecture/data-model.md`, the ERD: T2 and T3.
  18. `c4-context-system`, `c4-container-system`: T18.
  19. `docs/design.md` and its mock: the note was added on 2026-11-26, in its own commit.
      Since then the owner put "All regions" first among the region choices; the mock
      draws it last and the note does not say so. Offered to the owner as a fifth line of
      the note; not answered, not done.
  20. The home page: T8.
  21. The Admin's Regions screens: no change (plan decision 16).
- T19, not done or not checked, in one place: CI (nothing is pushed); the tap on a real
  phone; the job-details block in a search engine's own checker; the screenshots of the
  phone check beyond the ones named in each task.
- 2026-11-27, the owner went through the four open items one at a time:
  1. Rows on the first screen: left as built. Spec decision 27; the non-functional
     requirement says what is built. Kept as a product idea in `TODO.md`, written up in
     `scratchpad/product_ideas/` (not in git).
  2. "Share" on a real phone: after the site is deployed. Phones allow the share sheet
     and copying only on a secure address, which the dev machine does not have, so a
     phone today would show only the last fallback. **Open check**, listed in `TODO.md`:
     once deployed, open a listing on a phone, tap "Share", and see the share sheet with
     the title and the address. The spec is marked Done with this one check outstanding.
  3. The design guide's note: a fifth sentence, on "All regions" being first. Done in its
     own commit, with a changelog row.
  4. Push, wait for CI, mark Done (T20).
- T20: pushed on the owner's word, 38 commits, `af7b95c..3c7de0f`. CI ran `mix precommit`
  on a clean machine: success (run 46064859189). Then the spec, the plan, this file and
  the 005 row of spec 000's feature map were set to Done and pushed; that push changes
  documents only, so CI skips it (constitution §3.10).
- At Done, what is still open, all of it in `TODO.md`: the tap on "Share" on a real
  phone and the job details in a search engine's checker, both after deployment; and the
  idea of showing more jobs on the first phone screen. Deployment itself stays parked.
