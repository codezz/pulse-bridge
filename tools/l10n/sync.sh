#!/bin/bash
# Pulls the texts used in source into the String Catalogs (Xcode does this only in its editor).
# Usage: tools/l10n/sync.sh /tmp/pb-dd   (after an app build with that derived data path)
set -euo pipefail
dd=${1:?derived data path}
cd "$(dirname "$0")/../.."
sync() {   # catalog, build directory name of the target
  local args=()
  while IFS= read -r f; do args+=(--stringsdata "$f"); done < <(
    find "$dd/Build/Intermediates.noindex" -path "*-iphonesimulator/$2/*" -path '*arm64*' -name '*.stringsdata' ! -name 'ExtractedAppShortcutsMetadata.stringsdata')
  if [ ${#args[@]} -eq 0 ]; then echo "no strings found for $2 (build first)" >&2; exit 1; fi
  xcrun xcstringstool sync "$1" "${args[@]}"
}
sync PulseBridge/Localizable.xcstrings PulseBridge.build
sync PulseBridgeWidgets/Localizable.xcstrings PulseBridgeWidgets.build
sync PulseKit/Sources/PulseKit/Localizable.xcstrings PulseKit.build
sync PulseKit/Sources/PulseBLE/Localizable.xcstrings PulseBLE.build
