#!/usr/bin/env python3
"""Open pages at phone width in a headless browser and measure them.

The browser half of scripts/phone-check.sh; it knows nothing about any spec.
A hand-run layout check, not a test (constitution §3.1).

Usage: phone-check.py PAGES.json BASE_URL OUT_DIR

PAGES.json is what a priv/phone_check/NNN.exs prints on `setup`:

    {"sessions": [
       {"name": "admin", "login": "/users/log-in/<token>",
        "pages": [{"name": "queue", "path": "/admin/listings",
                   "steps": [["fill", "<selector>", "text"], ["click", "<selector>"]]}]}]}

`steps` is optional: what to do on the page before it is measured.

For each page it checks, at 375 px wide:
  * the document is no wider than the viewport (no sideways scrolling);
  * every visible tap target is at least 44 px tall (docs/design.md, "Tap target"):
    buttons, links styled as buttons, links in a <nav>, and links that fill a list row.
Text fields, selects and text areas under 44 px are listed as notes; they do not fail a page.

A full-page screenshot of each page is saved to OUT_DIR. Exits 1 if any page failed.
"""
import json
import os
import sys

WIDTH, HEIGHT, MIN_TAP = 375, 800, 44

MEASURE = """
([width, minTap]) => {
  const seen = el => {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return null;
    if (!el.checkVisibility({visibilityProperty: true, opacityProperty: true})) return null;
    if (r.right <= 0 || r.left >= width) return null;   // off-canvas, e.g. the closed drawer
    return r;
  };
  const label = el =>
    (el.id ? '#' + el.id : (el.getAttribute('aria-label') || el.textContent || el.tagName))
      .trim().replace(/\\s+/g, ' ').slice(0, 40);
  const short = selector => {
    const out = [];
    for (const el of document.querySelectorAll(selector)) {
      const r = seen(el);
      if (r && Math.round(r.height) < minTap) out.push(label(el) + ' (' + Math.round(r.height) + ' px)');
    }
    return [...new Set(out)];
  };
  const wide = [];
  for (const el of document.querySelectorAll('body *')) {
    const r = seen(el);
    if (r && r.right > width + 0.5) wide.push(label(el) + ' (to ' + Math.round(r.right) + ' px)');
  }
  return {
    scrollWidth: document.documentElement.scrollWidth,
    wide: [...new Set(wide)].slice(0, 5),
    taps: short('button, .btn, [role="button"], label[for], nav a, li > a'),
    fields: short('input:not([type="hidden"]):not([type="checkbox"]):not([type="radio"]), select, textarea'),
  };
}
"""


def connected(page):
    """Wait for a LiveView page to connect; plain pages have nothing to wait for."""
    if page.locator("[data-phx-main]").count():
        page.wait_for_selector("[data-phx-main].phx-connected", timeout=15000)
    page.wait_for_timeout(300)


def log_in(page, base, path):
    page.goto(base + path)
    connected(page)
    page.locator("form button").first.click()
    page.wait_for_url(lambda url: "/users/log-in/" not in url, timeout=15000)


def main():
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit("playwright is not installed for this Python: "
                 "pip install playwright && playwright install chromium")

    pages_file, base, out = sys.argv[1:4]
    sessions = json.load(open(pages_file))["sessions"]
    os.makedirs(out, exist_ok=True)
    results = []

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for session in sessions:
            context = browser.new_context(
                viewport={"width": WIDTH, "height": HEIGHT}, device_scale_factor=2)
            page = context.new_page()
            if session.get("login"):
                log_in(page, base, session["login"])

            for entry in session["pages"]:
                name = f'{session["name"]}-{entry["name"]}'
                try:
                    page.goto(base + entry["path"])
                    connected(page)
                    for step in entry.get("steps", []):
                        if step[0] == "fill":
                            page.fill(step[1], step[2])
                        elif step[0] == "click":
                            page.locator(step[1]).click()
                        page.wait_for_timeout(400)
                    found = page.evaluate(MEASURE, [WIDTH, MIN_TAP])
                    page.screenshot(path=os.path.join(out, name + ".png"), full_page=True)
                except Exception as error:  # a page that cannot be opened has failed
                    results.append((name, [f"could not be checked: {str(error).splitlines()[0]}"], []))
                    continue

                problems = []
                if found["scrollWidth"] > WIDTH:
                    problems.append(f'{found["scrollWidth"]} px wide: ' + ", ".join(found["wide"]))
                if found["taps"]:
                    problems.append(f"under {MIN_TAP} px tall: " + ", ".join(found["taps"]))
                results.append((name, problems, found["fields"]))
            context.close()
        browser.close()

    failed = 0
    for name, problems, fields in results:
        print(("FAIL " if problems else "OK   ") + name)
        for problem in problems:
            print("       " + problem)
        if fields:
            print(f"       note, fields under {MIN_TAP} px: " + ", ".join(fields))
        failed += 1 if problems else 0

    print(f"{len(results)} page(s) checked at {WIDTH} px, {failed} failed. Screenshots: {out}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
