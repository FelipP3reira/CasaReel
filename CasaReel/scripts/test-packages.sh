#!/bin/bash
# Builds and tests every local package in isolation on the iOS Simulator.
# Each package resolves only its own declared dependencies, so an undeclared
# import (e.g. a Feature importing another Feature) fails here.
set -euo pipefail
cd "$(dirname "$0")/../Packages"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17e}"
DERIVED_DATA="${DERIVED_DATA:-${TMPDIR:-/tmp}/casareel-packages-dd}"
failed=()

for package in */; do
  package="${package%/}"
  echo "▸ $package"
  if ! (cd "$package" && xcodebuild test -scheme "$package" -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED_DATA/$package" -quiet); then
    failed+=("$package")
  fi
done

if (( ${#failed[@]} )); then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All packages passed."
