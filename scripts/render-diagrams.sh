#!/usr/bin/env bash
# Render all PlantUML sources in docs/architecture/diagrams/src/ to SVG in ../out/.
# Run after editing any .puml and commit the SVGs in the same commit.
#
# Usage: scripts/render-diagrams.sh
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="docs/architecture/diagrams/src"
OUT="docs/architecture/diagrams/out"

command -v plantuml >/dev/null || { echo "plantuml not found (brew install plantuml)"; exit 1; }

mkdir -p "$OUT"
shopt -s nullglob
files=("$SRC"/*.puml)

if [ ${#files[@]} -eq 0 ]; then
  echo "No .puml files in $SRC"
  exit 0
fi

plantuml -tsvg -o "../out" "${files[@]}"
echo "Rendered ${#files[@]} diagram(s) to $OUT/"
