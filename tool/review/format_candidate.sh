#!/usr/bin/env bash
set -Eeuo pipefail

git fetch --no-tags origin main
mapfile -d '' dart_files < <(
  git diff --name-only -z --diff-filter=ACMR origin/main...HEAD -- '*.dart'
)
if (( ${#dart_files[@]} > 0 )); then
  dart format "${dart_files[@]}"
fi
