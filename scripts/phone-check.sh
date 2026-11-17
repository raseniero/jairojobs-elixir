#!/usr/bin/env bash
# Check a spec's screens at phone width (375 px) in a headless browser.
#
# A hand-run layout check for the Definition of Done item "Works at 375 px width".
# It is not a test: the suite has no browser tests (constitution §3.1), and this is
# never run by `mix precommit` or CI.
#
# What it does:
#   1. counts the listings, users and regions in the dev database;
#   2. runs `priv/phone_check/NNN.exs setup`, which creates throwaway data (all named
#      "phonecheck…") and prints the pages to open and a log-in link per account;
#   3. starts the dev server on a spare port, unless one is already answering there;
#   4. opens each page at 375 px (scripts/phone-check.py), checks its width and its
#      tap targets, and saves a screenshot to tmp/phone-check/NNN/;
#   5. removes the throwaway data and stops the server it started, even after a
#      failure, and checks the database counts are what they were.
#
# Look at the screenshots: a page can pass both measurements and still look wrong.
#
# Needs Python 3 with Playwright and its Chromium:
#   pip install playwright && playwright install chromium
# Set PHONE_CHECK_PYTHON if that Python is not the first `python3` on your PATH.
#
# Usage: scripts/phone-check.sh NNN        e.g. scripts/phone-check.sh 004
#        PHONE_CHECK_PORT=4011 scripts/phone-check.sh 004
set -euo pipefail

cd "$(dirname "$0")/.."

spec="${1:-}"
file="priv/phone_check/${spec}.exs"
[ -n "$spec" ] && [ -f "$file" ] || {
  echo "usage: scripts/phone-check.sh NNN   (pages files: $(ls priv/phone_check | grep -E '^[0-9]+\.exs$' | tr '\n' ' '))"
  exit 2
}

# A Python that has Playwright: the one named, the default, or the one beside `playwright`.
python=""
for candidate in "${PHONE_CHECK_PYTHON:-}" python3 "$(dirname "$(command -v playwright || echo /nonexistent/x)")/python"; do
  if [ -n "$candidate" ] && command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c "import playwright" >/dev/null 2>&1; then
    python="$candidate"
    break
  fi
done
[ -n "$python" ] || {
  echo "No Python with Playwright found."
  echo "  pip install playwright && playwright install chromium"
  echo "or set PHONE_CHECK_PYTHON to a Python that has it."
  exit 2
}

port="${PHONE_CHECK_PORT:-4010}"
base="http://localhost:${port}"
out="tmp/phone-check/${spec}"
log="tmp/phone-check/server-${spec}.log"
mkdir -p "$out"
rm -f "$out"/*.png

# One marked line of output from the pages file, e.g. `marked COUNTS counts`.
marked() {
  local marker="PHONECHECK_$1:"
  shift
  mix run "$file" "$@" 2>&1 | grep "^${marker}" | tail -1 | sed "s/^${marker}//"
}

before="$(marked COUNTS counts)"
[ -n "$before" ] || { echo "could not read the dev database (is it created and migrated?)"; exit 2; }

server_pid=""
finish() {
  status=$?
  trap - EXIT
  echo "Removing the throwaway data…"
  marked CLEANUP cleanup || true
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  after="$(marked COUNTS counts)"
  if [ "$after" != "$before" ]; then
    echo "WARNING: the dev database changed. listings,users,regions before: $before  after: $after"
    echo "         Look for names starting with \"phonecheck\" and run: mix run $file cleanup"
    status=1
  else
    echo "Dev database unchanged (listings,users,regions: $after)."
  fi
  exit "$status"
}
trap finish EXIT

echo "Creating throwaway data for spec ${spec}…"
marked JSON setup >"$out/pages.json"
[ -s "$out/pages.json" ] || { echo "the pages file printed no pages"; exit 1; }

if curl -s -o /dev/null "$base/"; then
  echo "Using the server already running on port ${port}."
else
  echo "Starting the dev server on port ${port}…"
  PORT="$port" mix phx.server >"$log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "$base/" && break
    kill -0 "$server_pid" 2>/dev/null || { echo "the server stopped; see $log"; exit 1; }
    sleep 1
  done
  curl -s -o /dev/null "$base/" || { echo "the server did not answer on port ${port}; see $log"; exit 1; }
fi

"$python" scripts/phone-check.py "$out/pages.json" "$base" "$out"
