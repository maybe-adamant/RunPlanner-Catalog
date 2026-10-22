#!/usr/bin/env bash
# Validates every entry folder with a local Run Planner checkout, as the pull request check does:
#   scripts/check-local.sh <path-to-RunPlanner-checkout>
# The checkout needs its dependencies installed (npm ci) and a Rust toolchain.
set -euo pipefail

planner="${1:?usage: scripts/check-local.sh <path-to-RunPlanner-checkout>}"
repository="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "${out}"' EXIT

if [ ! -f "${planner}/scripts/catalog-build.mjs" ]; then
  echo "${planner} has no scripts/catalog-build.mjs; use a planner release with the catalog." >&2
  exit 1
fi
(cd "${planner}" && npm run --silent catalog:build -- --entries "${repository}/entries" \
  --categories "${repository}/categories.json" --out "${out}")
(cd "${planner}" && cargo run --quiet --manifest-path apps/planner/src-tauri/Cargo.toml \
  -p run-planner-game-host --example catalog_ci -- check "${out}/catalog.json")
cat "${out}/summary.txt"
