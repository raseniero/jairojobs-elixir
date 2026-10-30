# 001 — Accounts & Authentication

**Status:** Draft
**Created:** 2026-10-29
**Owner:** Jairo
**Related ADRs:** 0004 (UUID v7 keys)
**Depends on:** 000 (product overview)

## Problem / Why

Every other feature depends on knowing who the user is and what role they hold. Candidates
must sign in to apply and to own a profile; employers must sign in to post; admins must be
identifiable to moderate. Visitors must *not* be forced to sign in to browse.

We need a secure, low-friction authentication system that works well on phones. Signup should
be as simple as entering an email; email ownership is proven by clicking a link; a password is
optional convenience added later.

## Goals

- Visitors browse without an account.
- Anyone can sign up as a **Candidate** or **Employer**; the role is chosen at signup and one
  account has exactly one role.
- Email is confirmed before the account can be used (clicking the signup link both confirms
  and logs in — no separate confirmation step).
- Login via **magic link** (always) and via **email + password** (once a password is set).
- Users can manage their email and password in Settings.
- An **Admin** role exists; it is granted only via a privileged mechanism, never via signup.
  Admins can promote/demote other users.
- Establish the **`Scope`** (current user + role) passed to every context function, as the
  foundation for authorization in all later specs.

## Non-goals / Out of scope

- Social login (Google / Facebook) — deferred; may become its own spec later.
- Two-factor authentication.
- Multi-user employer / company accounts.
- Collecting names, business names, or any profile data at signup — that belongs to
  spec 006 (Profiles) and spec 003 (Listings).
- Employer business verification — handled by listing approval (spec 004).
- Account deletion / data export — later spec.
- Rate limiting / CAPTCHA beyond what the generator provides — revisit if abuse appears.

## Personas involved

- **Visitor** — browses without an account; may sign up.
- **Candidate** — signs up, logs in, manages settings.
- **Employer** — signs up, logs in, manages settings.
- **Admin** — created via privileged mechanism; logs in like any user; promotes/demotes.

## User stories

- **US-001-1** — As a Visitor, I want to browse listings without creating an account, so that
  I can see if the site is useful before committing.
- **US-001-2** — As a Visitor, I want to sign up with just my email and pick whether I'm looking
  for work or hiring, so that getting started takes seconds on my phone.
- **US-001-3** — As a Candidate/Employer, I want to log in by clicking a link in my email, so
  that I don't have to remember a password.
- **US-001-4** — As a Candidate/Employer, I want to optionally set a password, so that I can
  log in faster on a device where email is inconvenient.
- **US-001-5** — As a Candidate/Employer, I want to change my email or password, so that I keep
  control of my account.
- **US-001-6** — As a Candidate/Employer, I want to log out, so that nobody else on a shared
  phone can act as me.
- **US-001-7** — As a Candidate/Employer, I want the site to show me the right menu for my
  account type, so that I'm not confused by options that don't apply to me.
- **US-001-8** — As the operator, I want to create the first Admin without a public admin
  signup, so that nobody can self-grant moderation powers.
- **US-001-9** — As the operator, I want to promote a trusted user to Admin (and demote), so
  that moderation can be shared as the community grows.

## Requirements

### REQ-001-1: Public browsing requires no account

**Serves:** US-001-1

Unauthenticated visitors can reach all public pages (home, listing index, listing detail, and
the sign-up / log-in pages). Only protected pages redirect to log-in.

**Acceptance criteria**
- Given I am not logged in, when I open the home page or any public listing page, then it
  renders without redirecting me to log in.
- Given I am not logged in, when I open a protected page (e.g. settings), then I am redirected
  to the log-in page and, after logging in, returned to the page I asked for.

### REQ-001-2: Sign up with email and role

**Serves:** US-001-2

A visitor signs up with an email address and a role (`candidate` or `employer`). No password
is collected at signup. A confirmation/login link is emailed.

**Acceptance criteria**
- Given I am on the sign-up page, when I submit a valid email and choose a role, then an
  account is created with that role, and a login link is emailed to that address.
- Given I submit the form without choosing a role, then I see a validation error and no
  account is created.
- Given I submit an email that is already registered, then I see the same neutral success
  message as a new signup (no account enumeration), and no duplicate account is created.
- Given I submit an invalid email format, then I see a validation error.
- The role cannot be `admin` from the sign-up form, even if the parameter is forged.

### REQ-001-3: Email is confirmed by using the first login link

**Serves:** US-001-2, US-001-3

Clicking the emailed link confirms the email address and logs the user in. Until confirmed,
the account cannot log in by any method.

**Acceptance criteria**
- Given I signed up and have not clicked the link, when I try to log in with magic link or
  password, then I cannot get a session (magic-link email is re-sent instead; password login
  is refused).
- Given I click the valid link from the signup email, then my account is marked confirmed and
  I am logged in.
- Given the link is expired or already used, when I click it, then I see an error and am not
  logged in.

### REQ-001-4: Log in via magic link

**Serves:** US-001-3

A confirmed user can request a login link by email at any time.

**Acceptance criteria**
- Given I enter my registered email on the log-in page and request a link, then I receive an
  email with a single-use link; clicking it logs me in.
- Given I enter an unregistered email, then I see the same neutral message (no enumeration)
  and no email is sent.
- Given the link has already been used or has expired, then it does not log me in.

### REQ-001-5: Optional password; log in via email + password

**Serves:** US-001-4

A logged-in user may set a password in Settings. Once set, email + password login works in
addition to magic link.

**Acceptance criteria**
- Given I am logged in and have no password, when I set a valid password in Settings, then I
  can subsequently log in with email + password.
- Given I have a password, when I log in with the wrong password, then I see a generic
  "invalid email or password" error.
- Given I have a password but my email is unconfirmed (edge case), when I try password login,
  then I am refused (per REQ-001-3).
- Password rules: minimum 12 characters, maximum 72 bytes.

### REQ-001-6: Change email

**Serves:** US-001-5

A logged-in user can change their email; the change takes effect only after the new address
is confirmed via a link.

**Acceptance criteria**
- Given I am logged in, when I submit a new email in Settings, then a confirmation link is
  sent to the **new** address and my current email remains unchanged.
- Given I click the link sent to the new address, then my account email is updated.
- Given the new email is already used by another account, then I see a validation error.

### REQ-001-7: Change password

**Serves:** US-001-5

**Acceptance criteria**
- Given I am logged in and have a password, when I enter my current password and a valid new
  password, then my password is updated and other sessions are logged out.
- Given I enter the wrong current password, then the change is rejected.

### REQ-001-8: Log out

**Serves:** US-001-6

**Acceptance criteria**
- Given I am logged in, when I log out, then my session is invalidated and protected pages
  redirect me to log in again.

### REQ-001-9: Role is fixed and exposed via Scope

**Serves:** US-001-2, US-001-7

Each user has exactly one role: `candidate`, `employer`, or `admin`. The current user and
role are available to every LiveView/controller and passed to contexts as a `Scope`.

**Acceptance criteria**
- Given a user with role `candidate`, then `scope.user.role == :candidate` in any
  authenticated request.
- Users cannot change their own role through any user-facing form.
- Given I am logged in, when I open Settings, then I see my role as a read-only label
  ("Candidate" / "Employer" / "Admin").
- A role change (REQ-001-10/11) takes effect on the user's next request.

### REQ-001-10: Admin promotion / demotion via privileged command

**Serves:** US-001-8, US-001-9

Admins are created and removed by the operator outside the web UI, using a command run with
server access (a `mix` task locally; a release command in production). There is no admin
sign-up page and **no promote/demote web UI in this spec** — that arrives with the admin
dashboard (spec 008) and will call the same context functions.

**Acceptance criteria**
- Given a registered, confirmed user email, when the operator runs the promote command with
  that email, then the user's role becomes `admin`.
- Given an admin's email, when the operator runs the demote command, then the role reverts to
  the role held before promotion (or `candidate` if unknown).
- Given an email that does not exist, then the command fails with a clear message and changes
  nothing.
- Given the target is the only admin, when the operator runs demote, then it is refused.
- The command is documented in `plan.md` and the project `README.md`.

### REQ-001-11: Promote / demote rules live in the Accounts context

**Serves:** US-001-8, US-001-9

The rules behind REQ-001-10 are implemented as context functions taking a `Scope`, so the
command now and the admin UI later (spec 008) share one tested implementation.

**Acceptance criteria**
- Given an admin scope, when promoting a candidate or employer, then their role becomes
  `admin` and their previous role is remembered.
- Given an admin scope, when demoting another admin, then their role reverts to the remembered
  role (or `candidate` if unknown).
- Given the target is the last remaining admin, when demoting, then it is refused (no lock-out).
- Given a non-admin scope, when calling promote or demote, then it is refused and nothing
  changes.
- The privileged command runs with a system/operator scope that is treated as admin.

### REQ-001-12: Role-aware navigation

**Serves:** US-001-7

The layout shows the right entry points for the current role.

**Acceptance criteria**
- Given I am a Visitor, then I see "Log in" and "Sign up".
- Given I am a Candidate, then I see links to my applications/profile (placeholders until
  specs 006/007) and Settings.
- Given I am an Employer, then I see a link to my listings (placeholder until spec 003) and
  Settings.
- Given I am an Admin, then I additionally see an Admin link.

## Non-functional requirements

- **Security:** tokens are single-use and expire (magic link ≤ 15 min, email-change ≤ 1 day,
  session ≤ 60 days with sudo-mode re-auth for sensitive settings as generated); all tokens
  revoked on first confirmation (generator default); no account enumeration on sign-up or
  magic-link request.
- **Mobile-first:** sign-up and log-in forms are usable one-handed at 375 px; email input uses
  `type="email"` + `autocomplete`; no CAPTCHA in phase 1.
- **Email delivery:** dev uses the local Swoosh mailbox; production adapter chosen at deploy
  (spec note, not blocking).
- **Privacy:** no PII in logs (constitution §4.12).

## Resolved questions

| Question | Decision |
|---|---|
| Show role in Settings? | Yes, read-only label (REQ-001-9) |
| Promote/demote UI now? | No. Command + context logic now (REQ-001-10/11); UI in spec 008 |
| Social login? | Deferred; possible future spec |

## Open questions

- None.

## Traceability

| Story | Requirements |
|---|---|
| US-001-1 | REQ-001-1 |
| US-001-2 | REQ-001-2, REQ-001-3, REQ-001-9 |
| US-001-3 | REQ-001-3, REQ-001-4 |
| US-001-4 | REQ-001-5 |
| US-001-5 | REQ-001-6, REQ-001-7 |
| US-001-6 | REQ-001-8 |
| US-001-7 | REQ-001-9, REQ-001-12 |
| US-001-8 | REQ-001-10, REQ-001-11 |
| US-001-9 | REQ-001-10, REQ-001-11 |

## Changelog

| Date | Change |
|---|---|
| 2026-10-29 | Created |
| 2026-10-29 | Resolved open questions: role label in Settings; command-only admin management |
| 2026-10-29 | Numbered user stories (US-001-n), added Serves: links and traceability table |
