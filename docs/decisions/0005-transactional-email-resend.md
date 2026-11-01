# 0005 — Transactional email via Resend from hello@jairojobs.com

**Status:** Accepted
**Date:** 2026-10-30
**Supersedes:** —
**Superseded by:** —

## Context

Authentication is magic-link based (spec 001): if email doesn't arrive, users cannot log in.
Later specs also send application and notification emails. Phoenix ships Swoosh with a local
adapter for dev and a test adapter for tests, but production needs a real provider, a sending
domain, and DNS authentication (SPF/DKIM/DMARC) or mainstream inboxes (Gmail, Yahoo, Outlook —
the majority of Philippine users) will junk or drop the mail.

We own `jairojobs.com`. Swoosh 1.29 includes `Swoosh.Adapters.Resend`, so no extra dependency
is required.

## Decision

- **Provider:** Resend (free tier 3,000 emails/month; API-based; built-in Swoosh adapter).
- **Sending domain:** `jairojobs.com`, verified in Resend with DKIM + SPF (+ DMARC `p=none`
  initially).
- **Sender:** `"jairojobs" <hello@jairojobs.com>` for all transactional mail. A real mailbox
  must exist for `hello@` so replies don't bounce.
- **Configuration:** sender in `config :jairojobs, :mailer_from`; production adapter + API key
  in `config/runtime.exs` from `RESEND_API_KEY` (Fly secret). Dev keeps
  `Swoosh.Adapters.Local` (`/dev/mailbox`); test keeps `Swoosh.Adapters.Test`.
- **API keys:** one per environment, sending-only, domain-restricted.

## Consequences

**Positive**
- Zero new deps; a few lines of config.
- Good deliverability once DNS is verified; dashboard shows delivered/bounced per email, which
  is essential for debugging "I never got my link."
- Free tier comfortably covers community scale; pay-as-you-grow after.

**Negative / trade-offs**
- Vendor dependency; switching providers means a new adapter + DNS, though Swoosh makes the
  code change trivial.
- Daily cap on free tier (100/day) could be hit during a launch spike — monitor, upgrade if
  needed.
- DNS setup is a manual, one-time step outside the codebase; documented in the deployment plan.

## Alternatives considered

- **Postmark** — excellent deliverability but a small free tier and stricter onboarding.
- **Amazon SES** — cheapest at scale; more setup (IAM, sandbox exit, region) than warranted now.
- **SMTP via Google Workspace** — not designed for transactional volume; rate limits and
  reputation risk.
- **Mailgun / SendGrid / Brevo** — comparable; no advantage over Resend's simpler API.
