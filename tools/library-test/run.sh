#!/bin/bash
# Builds the library test from the app's own sources and runs it on a copy of a library folder.
#   tools/library-test/run.sh /tmp/brownie-copy
set -euo pipefail
cd "$(dirname "$0")/../.."
out="${TMPDIR:-/tmp}/brownie-library-test"
xcrun swiftc -O -o "$out" \
  tools/library-test/main.swift \
  MeditationApp/MeditationLibrary.swift \
  MeditationApp/EraIndex.swift \
  "MeditationApp/FileManager+Meditations.swift"
"$out" "$1"
