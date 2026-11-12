# Jairojobs

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

In development, every email the app sends (sign-up and login links, email-change
confirmations) is viewable at [`localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox).

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
time. Approving listings is spec 004, so until that ships a submitted listing stays
"Waiting for approval".

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

In production the same functions will be exposed through `Jairojobs.Release` once the
release tooling lands (see `docs/specs/001-accounts-authentication/plan.md`).

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
