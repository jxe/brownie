#!/bin/bash
# Builds the one-off sort from the app's own sources and runs it.
#   tools/sort-library/run.sh <library folder> --dry-run
#   tools/sort-library/run.sh <library folder> --backup ~/brownie-backups
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/brownie-sort-library"
xcrun swiftc -O -o "$out" \
  tools/sort-library/main.swift \
  MeditationApp/MeditationLibrary.swift \
  MeditationApp/EraIndex.swift \
  "MeditationApp/FileManager+Meditations.swift"
"$out" "$@"
