# Design Guide

**Status:** Accepted
**Last updated:** 2026-10-31
**Brief:** "A clean, trustworthy, modern craigslist.org."

The single reference for how jairojobs looks and feels. Agents and humans build every screen
from this document; no per-screen visual design. Layout is sketched per screen with Salt
wireframes (README diagram rule 6); visuals come from here.

Reference render (375 px, listing index + detail):

![Listing mock at 375 px](design/mock-listing-375.png)

*Source: `design/mock-listing-375.html` (static HTML, same tokens). Open in a browser to inspect.*

## 1. Principles

1. **Text is the interface.** Listings are a list, not cards. No stock photos, no hero
   banners, no carousels. Content first, chrome last.
2. **Fast and light.** System font stack, no web fonts, minimal JS, no third-party embeds.
   A listing page must be readable on a mid-range Android over 4G in under 2 s.
3. **Nothing hidden.** Salary, region, posted date, employer name, and moderation status are
   always visible. No dark patterns, no fake urgency, no "salary negotiable."
4. **One accent colour, used once per screen** — for the primary action only (Apply, Post a
   job, Approve). Everything else is neutral or the primary blue.
5. **Craigslist density, thumb-friendly.** Compact rows (≈ 6 listings per phone screen) but
   every interactive element is at least 44 px tall.
6. **Plain language.** Microcopy says what will happen ("We'll email you a sign-in link"),
   never jargon ("Authenticate").
7. **Mobile first, desktop inherits.** Design and test at 375 px; wider screens get more
   margin, not more features. Max content width 720 px.

## 2. Tokens

| Token | Value | Tailwind | Use |
|---|---|---|---|
| Page background | `#ffffff` | `bg-base-100` | pages |
| Section background | `#f8fafc` | `bg-base-200` / slate-50 | filters bar, fact boxes, footers |
| Border | `#e2e8f0` | `border-base-300` / slate-200 | row dividers, inputs, cards |
| Text | `#0f172a` | `text-base-content` / slate-900 | body |
| Muted text | `#64748b` | slate-500 | meta, hints, timestamps |
| **Primary** | `#1d4ed8` | `text-primary` / blue-700 | listing titles, links, selected chips, secondary buttons |
| **Accent (CTA)** | `#d97706` | `btn-accent` / amber-600 | the one primary action per screen |
| Success | `#059669` | emerald-600 | "✓ Approved" badge, success flash |
| Warning | `#d97706` | amber-600 | pending states |
| Error | `#dc2626` | red-600 | validation, destructive |
| Font | system stack | default `font-sans` | everything; no web fonts |
| Base size | 16 px | `text-base` | body |
| Listing title | 17 px / 600 | `text-[17px] font-semibold` | index rows |
| Page title | 22 px / 700 | `text-[22px] font-bold` | detail pages |
| Meta | 14 px | `text-sm` | salary, date, region |
| Fine print | 12–13 px | `text-xs` | hints, footers |
| Radius | 6 px | `rounded-md` | buttons, inputs, boxes |
| Pill radius | 999 px | `rounded-full` | chips, badges |
| Row padding | 12 px × 16 px | `py-3 px-4` | list rows |
| Tap target | ≥ 44 px | `min-h-11` | buttons, rows, links in nav |
| Content width | 720 px | `max-w-[720px] mx-auto` | all pages |
| Theme | light only | — | dark deferred |
| Icons | Heroicons outline 20 px | `<.icon name="hero-…" class="size-5"/>` | stock only |

## 3. daisyUI theme

The tokens are encoded as the single daisyUI theme in `assets/css/app.css`. Replace the
generated `light` and `dark` theme blocks with this one (dark removed; `prefersdark: false`).

```css
@plugin "daisyui/packages/bundle/daisyui-theme" {
  name: "jairojobs";
  default: true;
  prefersdark: false;
  color-scheme: "light";
  --color-base-100: oklch(100% 0 0);            /* white */
  --color-base-200: oklch(98.4% 0.003 247.9);   /* slate-50  #f8fafc */
  --color-base-300: oklch(92.9% 0.013 255.5);   /* slate-200 #e2e8f0 */
  --color-base-content: oklch(20.8% 0.042 265.8); /* slate-900 #0f172a */
  --color-primary: oklch(48.8% 0.243 264.4);    /* blue-700  #1d4ed8 */
  --color-primary-content: oklch(100% 0 0);
  --color-secondary: oklch(55.4% 0.046 257.4);  /* slate-500 #64748b */
  --color-secondary-content: oklch(100% 0 0);
  --color-accent: oklch(66.6% 0.179 58.3);      /* amber-600 #d97706 */
  --color-accent-content: oklch(100% 0 0);
  --color-neutral: oklch(37.2% 0.044 257.3);    /* slate-700 */
  --color-neutral-content: oklch(100% 0 0);
  --color-info: oklch(62.3% 0.214 259.8);       /* blue-500 */
  --color-info-content: oklch(100% 0 0);
  --color-success: oklch(59.6% 0.145 163.2);    /* emerald-600 #059669 */
  --color-success-content: oklch(100% 0 0);
  --color-warning: oklch(66.6% 0.179 58.3);     /* amber-600 */
  --color-warning-content: oklch(100% 0 0);
  --color-error: oklch(57.7% 0.245 27.3);       /* red-600 #dc2626 */
  --color-error-content: oklch(100% 0 0);
  --radius-selector: 0.375rem;
  --radius-field: 0.375rem;
  --radius-box: 0.375rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 0;
  --noise: 0;
}
```

`--depth: 0` and `--noise: 0` keep surfaces flat (no fake 3D). Use `btn-accent` for the CTA,
`btn-primary` for secondary actions, `btn-ghost` with border for tertiary (e.g. "Log in").

## 4. Patterns

### Listing row (index)
Title (primary, 17 px semibold) → employer · area (16 px) → salary (bold) · relative date ·
"✓ Approved" badge (14 px meta line). Whole row is the link. 12 px vertical padding, 1 px
divider. No thumbnails.

### Listing detail
Title → employer → trust line (badge · posted · region) → **facts box** (2-col grid on
base-200: salary, location, type, schedule) → sections with 15 px bold headings → sticky
bottom CTA with one line of plain-language hint beneath it.

### Trust signals (always)
- Salary range in PHP on every row and detail page.
- "✓ Approved" badge on published listings (admin moderation).
- Posted date (relative under 7 days, absolute after) and region on every row.
- Employer name always shown; no anonymous postings.
- Footer line on public lists: "Every listing shows salary and is checked by jairojobs before
  it goes live."

### Forms
Stock `<.input>` / `<.form>` from `core_components.ex`. Labels above fields, one column,
full-width on mobile, `type="email"` + `autocomplete` where relevant, inline errors in
`text-error`. Submit button is `btn-accent` only if it is the screen's primary action.

### Navigation
Per `specs/001-accounts-authentication/diagrams/wireframe-nav`: header with ☰, wordmark,
and one contextual button; drawer below `md`, inline links at `md+`.

### Empty / loading / error states
Plain sentences, no illustrations. Loading uses skeleton rows of the same height as listing
rows (no spinners for lists).

### Wordmark
`jairo` in text colour + `jobs` in primary, 18 px bold, `tracking-tight`. Placeholder until a
real logo exists; keep it text so it stays crisp and fast.

## 5. Do / Don't

| Do | Don't |
|---|---|
| Lists of rows with dividers | Card grids with shadows |
| One amber CTA per screen | Multiple competing coloured buttons |
| System fonts | Google Fonts / web fonts |
| Show the salary | "Competitive" / "Negotiable" / hidden salary |
| Relative dates ("2 h ago") | Raw timestamps |
| Short sentences in microcopy | Marketing adjectives |
| Heroicons outline | Emoji as icons, custom icon sets |
| Slate neutrals + blue + amber | Gradients, purple, brand-colour backgrounds |
| `--depth: 0` flat surfaces | Drop shadows, glassmorphism |
| Skeleton rows while loading | Spinners over empty space |

## 6. Accessibility

- Contrast ≥ 4.5:1 for text (all tokens above pass on white).
- Focus rings visible (daisyUI default `focus-visible` outline in primary).
- Every interactive element reachable by keyboard; drawer traps focus while open.
- `aria-label` on icon-only buttons (☰ = "Open menu").
- Respect `prefers-reduced-motion`; transitions ≤ 150 ms and non-essential.

## 7. Relationship to other documents

- ADR-0001 — stock CoreComponents + daisyUI (this guide is the theme for them).
- Constitution §2.4 (mobile-first), §4.9 (components), §5 (no UI library).
- `AGENTS.md` — the generated line "manually write your own tailwind-based components instead
  of using daisyUI" is overridden by ADR-0001 and this guide: use daisyUI classes from the
  `jairojobs` theme and the stock `core_components.ex`.
