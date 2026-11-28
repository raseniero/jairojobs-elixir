# TODO

Things to come back to. Not a plan: nothing here is approved work. Feature work still
starts with a spec (`docs/README.md`).

## Checks still to do

- **"Share" on a real phone, now that the site is deployed** (spec 005, REQ-005-8). Open a
  listing on a phone, tap "Share", and see the phone's share sheet open with the job's
  title and its address. It cannot be done before deployment: phones allow the share
  sheet and copying only on a secure (https) address. Six cases passed in a simulated
  browser (spec 005 `tasks.md`, T16). Write the result in that `tasks.md`.
- **The job details in a search engine's own checker, now that the site is deployed**
  (spec 005, REQ-005-9). Put a listing's address through Google's Rich Results Test and
  see that it reads the job posting. So far the block has only been parsed as JSON and
  compared field by field in tests.

## Before launch (the site is deployed at https://jairojobs.com since 2026-11-27)

- **Email on jairojobs.com is not set up yet.** Sign-in links depend on it. Verify the domain
  in Resend (DKIM and SPF records at GoDaddy), add `_dmarc` (`v=DMARC1; p=none;`), and create
  a real `hello@jairojobs.com` mailbox (ADR-0005). Then sign up with a real address and see
  the email arrive in the inbox.
- **The site is live before specs 006 and 007** (owner's decision, 2026-11-27, while still in
  development). Its listings cannot be applied to yet; decide when to announce it.

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
