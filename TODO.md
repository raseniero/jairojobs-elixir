# TODO

Things to come back to. Not a plan: nothing here is approved work. Feature work still
starts with a spec (`docs/README.md`).

## To fix

- **Spec 005's tests use fixed region names in tests that run at the same time.** Found on
  2026-11-27, after spec 005 was marked Done. Five new test files
  (`listings_public_test.exs`, `listing_live/index_test.exs`,
  `listing_controller_test.exs`, `sitemap_controller_test.exs`,
  `browse_journey_test.exs`) are `async: true` and create regions named "Davao City",
  "Cebu", "Baguio" and so on, because the addresses they check depend on the region's
  slug. Four tests added to older async files do the same
  (`listings_moderation_test.exs`, `employer/listing_live_test.exs`,
  `admin/listing_live_test.exs`). Region names are unique in the database, so such tests
  wait for each other, and can deadlock or time out on a busy machine. Spec 002's tests
  avoid this by being `async: false` with a comment; every other async test uses unique
  names ("Davao 1234"). The suite has passed every run so far, CI included, so this is a
  risk of an occasional false failure, not a wrong result. Fix: make the five files
  `async: false` with the same comment, and give the four added tests unique region names.

## Checks still to do

- **"Share" on a real phone, once the site is deployed** (spec 005, REQ-005-8). Open a
  listing on a phone, tap "Share", and see the phone's share sheet open with the job's
  title and its address. It cannot be done before deployment: phones allow the share
  sheet and copying only on a secure (https) address. Six cases passed in a simulated
  browser (spec 005 `tasks.md`, T16). Write the result in that `tasks.md`.
- **The job details in a search engine's own checker, once the site is deployed**
  (spec 005, REQ-005-9). Put a listing's address through Google's Rich Results Test and
  see that it reads the job posting. So far the block has only been parsed as JSON and
  compared field by field in tests.

## Before deploying

- **The site must be configured to answer at `jairojobs.com`.** The addresses in the
  sitemap, in a page's stated address, in the link preview and in the approval email are
  built from the address the site is configured with. On a dev machine that is
  `localhost`. `robots.txt` already names `https://jairojobs.com/sitemap.xml`.
- **Decide whether to deploy before specs 006 and 007.** After spec 005 a deployed site
  shows listings that nobody can apply to yet. Raised with the owner; not decided.

## Small things noticed (spec 005)

None is a fault in what was built. Each needs the owner's word before it is changed.

- **"✓ Approved" is green text in a thin green outline**, on the lists and on the listing
  page. The mock in the design guide draws a filled, tinted pill. The outline was chosen
  because the design guide's colours are checked for contrast on white, not on a tint.
- **A region far along the row of region choices can start off the screen on its own
  list.** With four regions the fourth is half visible. Nothing scrolls the row to the
  chosen region; that would need a small script.
- **On the listing page, a long region name makes the trust line wrap** and leaves a dot
  hanging at the end of its first line ("Posted 2 h ago ·").
- **On the ERD picture, a line crosses the label "located in"** and clips its first
  letter (`docs/architecture/diagrams/out/erd-jairojobs.svg`). The diagram is right.
- **The dev server's detailed log shows the values given to database queries**: an email
  address at log-in, a listing's text when it is saved. Older than spec 005. It does not
  happen at production's log level (`info`). Spec 005 switched this off for the two
  queries of a search, because the spec promises searched words are never logged
  (constitution §4.12 is the rule this touches).
- **Spec 005's `plan.md` says a few things that were built differently**: the order of
  two tasks, the kind of lock on a region's row, the id of a row on the lists, "All
  regions" first, the number of callers of `approve_listing`. Each difference is recorded
  in that spec's `tasks.md`; the plan was left as the record of what was planned.

## Product ideas

- **More jobs on the first phone screen.** On the lists of jobs, the region choices, the
  search box and the type filter sit above the list, so a visitor sees about five jobs
  before scrolling on a large phone and under four on a small one. The design guide hoped
  for about six. Left as built on 2026-11-27, at the close of spec 005. Ways to gain
  room, from moving the type filter beside the job count to folding search behind a
  button, are written up in
  `scratchpad/product_ideas/2026-11-27-more-jobs-on-first-phone-screen.md`. That folder
  is not in git: it is a working note on the owner's machine.
