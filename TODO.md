# TODO

Things to come back to. Not a plan: nothing here is approved work. Feature work still
starts with a spec (`docs/README.md`).

## Product ideas

- **More jobs on the first phone screen.** On the lists of jobs, the region choices, the
  search box and the type filter sit above the list, so a visitor sees about five jobs
  before scrolling on a large phone and under four on a small one. The design guide hoped
  for about six. Left as built on 2026-11-27, at the close of spec 005. Ways to gain
  room, from moving the type filter beside the job count to folding search behind a
  button, are written up in
  `scratchpad/product_ideas/2026-11-27-more-jobs-on-first-phone-screen.md`. That folder
  is not in git: it is a working note on the owner's machine.

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

