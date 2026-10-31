#!/usr/bin/env bash
# Render all PlantUML sources to SVG.
#   docs/architecture/diagrams/src/*.puml  ->  docs/architecture/diagrams/out/*.svg
#   docs/specs/*/diagrams/*.puml           ->  same folder (source and SVG side by side)
# Run after editing any .puml and commit the SVGs in the same commit.
#
# Usage: scripts/render-diagrams.sh
set -euo pipefail

cd "$(dirname "$0")/.."

command -v plantuml >/dev/null || { echo "plantuml not found (brew install plantuml)"; exit 1; }

shopt -s nullglob
count=0

# Architecture diagrams: src -> out
arch_src="docs/architecture/diagrams/src"
arch_out="docs/architecture/diagrams/out"
arch_files=("$arch_src"/*.puml)
if [ ${#arch_files[@]} -gt 0 ]; then
  mkdir -p "$arch_out"
  plantuml -tsvg -o "../out" "${arch_files[@]}"
  count=$((count + ${#arch_files[@]}))
fi

# Spec diagrams: render in place
for dir in docs/specs/*/diagrams; do
  spec_files=("$dir"/*.puml)
  if [ ${#spec_files[@]} -gt 0 ]; then
    plantuml -tsvg "${spec_files[@]}"
    count=$((count + ${#spec_files[@]}))
  fi
done

echo "Rendered $count diagram(s)"
