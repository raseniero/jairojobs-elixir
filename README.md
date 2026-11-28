# Jairojobs

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

In development, every email the app sends (sign-up and login links, email-change
confirmations, decisions on listings) is viewable at [`localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox).

## Regions

`mix setup` (and `mix run priv/repo/seeds.exs`) creates the launch regions — Davao City,
Cebu and Metro Manila (spec 002, REQ-002-5). The seed is safe to run again: it only inserts
what is missing and never undoes an admin's rename or hide. Admins manage the list at
`/admin/regions`.

## Posting a listing

Sign up as an Employer (or use an Admin account), then choose "Post a job". The first time
you are asked for your business name; after that you can save a draft with only a title,
finish it later, and submit it for approval. Your listings and their status are at
`/my/listings`. An Employer can have 3 listings open (waiting for approval or live) at a
time. A submitted listing stays "Waiting for approval" until an Admin approves it.

## Moderating listings

Admins find submitted listings at `/admin/listings` (also the first row of `/admin`, which
says how many are waiting). The page opens on the approval queue, longest-waiting first;
the other statuses are one tap away. Opening a listing shows it as visitors will see it,
with who posted it, and offers Approve, Reject (with a reason) and Edit, or Take down (with
a reason) for a live one. Taken down is final.

Each decision emails the listing's owner, and each submission emails every Admin. Nobody
is emailed about their own action, so to see these emails in development you need two
accounts: for example an Employer who submits a listing and an Admin who approves it.

## Checking specs against tests

Every Gherkin scenario in `docs/specs/` must have a test named `REQ-<id>: <scenario name>`
(constitution §3.2). To list scenarios that have none:

```bash
mix jairojobs.spec_coverage        # all specs
mix jairojobs.spec_coverage 003    # one spec
```

It exits non-zero if any scenario is uncovered. It is run by hand when closing a spec, not in CI.

## Checking screens at phone width

The Definition of Done asks that every screen works at 375 px. To check a spec's screens:

```bash
scripts/phone-check.sh 004
```

It creates throwaway data in the dev database (everything named `phonecheck…`), starts the
dev server on port 4010, opens each page listed in `priv/phone_check/004.exs` in a headless
browser at 375 px, and removes the data again. A page fails if it scrolls sideways or has an
interactive element under 44 px tall. Screenshots go to `tmp/phone-check/004/`; look at
them, because a page can pass both measurements and still look wrong.

It needs Python 3 with Playwright (`pip install playwright && playwright install chromium`);
set `PHONE_CHECK_PYTHON` if that is not your default `python3`. It is run by hand when
closing a spec, not by `mix precommit` or CI, and it is not a test. So far only spec 004 has
a pages file.

## Admin accounts

There is no admin sign-up. Admins are created and removed by the operator from the command
line (spec 001, REQ-001-10):

```bash
mix jairojobs.admin promote someone@example.com
mix jairojobs.admin demote  someone@example.com
```

Rules: the account must exist and have confirmed its email; demoting restores the role the
user had before promotion (candidate by default); the last remaining admin cannot be
demoted. The task prints one line and exits non-zero on failure.

In production the same rules run through `Jairojobs.Release` (see "Production" below).

## Production

The site runs on Fly.io: app `jairojobs` in Singapore (`sin`, ADR-0003), with Fly Managed
Postgres `jairojobs-db` on the Developer plan (ADR-0007). It answers at
`https://jairojobs.com`; `www.jairojobs.com` and `jairojobs.fly.dev` redirect there
(`REDIRECT_HOSTS` in `fly.toml`).

```bash
fly deploy -a jairojobs            # build, migrate (release_command), roll out
fly logs -a jairojobs              # when something goes wrong
fly secrets list -a jairojobs      # SECRET_KEY_BASE, DATABASE_URL, RESEND_API_KEY
```

Operator commands run inside the release:

```bash
fly ssh console -a jairojobs -C "/app/bin/jairojobs eval 'Jairojobs.Release.seed_regions()'"
fly ssh console -a jairojobs -C "/app/bin/jairojobs eval 'Jairojobs.Release.promote_admin(\"someone@example.com\")'"
fly ssh console -a jairojobs -C "/app/bin/jairojobs eval 'Jairojobs.Release.demote_admin(\"someone@example.com\")'"
```

The machine stops when idle and the database pauses after 15 minutes with no client, so
the first request after a quiet spell takes 20-30 s.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
