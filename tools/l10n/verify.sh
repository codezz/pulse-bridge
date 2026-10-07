#!/bin/bash
# Fails when the committed String Catalogs are out of date with the code or tools/l10n/ro.py, or a
# text has no Romanian. Run after an app build with that derived data path (CI does this).
# Usage: tools/l10n/verify.sh /tmp/pb-dd
set -euo pipefail
cd "$(dirname "$0")/../.."
tools/l10n/sync.sh "${1:?derived data path}"
python3 tools/l10n/ro.py > /dev/null
if ! git diff --quiet -- '*.xcstrings'; then
  echo "String Catalogs out of date: commit the changes from tools/l10n/sync.sh and ro.py:" >&2
  git diff --stat -- '*.xcstrings' >&2
  exit 1
fi
python3 tools/l10n/check.py
