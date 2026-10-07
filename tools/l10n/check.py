#!/usr/bin/env python3
"""Fails when a catalog key lacks a translated Romanian value, a key is stale, a translation has an
em-dash, or the Apple Health / diagnostics code goes through localization (it must stay English)."""
import json, pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[2]
catalogs = ["PulseBridge/Localizable.xcstrings", "PulseBridge/InfoPlist.xcstrings",
            "PulseBridgeWidgets/Localizable.xcstrings",
            "PulseKit/Sources/PulseKit/Localizable.xcstrings", "PulseKit/Sources/PulseBLE/Localizable.xcstrings"]
english_only = ["PulseBridge/HealthExporter.swift", "PulseBridge/ChallengeExporter.swift"] + \
    [str(p.relative_to(root)) for p in (root / "PulseKit/Sources/PulseKit/Diagnostics").glob("*.swift")]
problems = []


def translated(unit):
    if "stringUnit" in unit:
        return unit["stringUnit"].get("state") == "translated"
    variations = unit.get("variations", {})
    return bool(variations) and all(translated(v) for kind in variations.values() for v in kind.values())


for name in catalogs:
    data = json.loads((root / name).read_text())
    for key, entry in data["strings"].items():
        if entry.get("extractionState") == "stale":
            problems.append(f"{name}: stale key {key!r}")
        if entry.get("shouldTranslate") is False:
            continue
        ro = entry.get("localizations", {}).get("ro")
        if not ro or not translated(ro):
            problems.append(f"{name}: no Romanian for {key!r}")
        if "—" in json.dumps(entry, ensure_ascii=False):
            problems.append(f"{name}: em-dash in {key!r}")

for name in english_only:
    if re.search(r'String\(localized|LocalizedStringResource|\bL\(', (root / name).read_text()):
        problems.append(f"{name}: must stay English (no localization calls)")

print("\n".join(problems) or "l10n ok")
if problems:
    print(f"{len(problems)} problem(s)", file=sys.stderr)
sys.exit(1 if problems else 0)
