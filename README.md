# Pulse Bridge

An open-source iPhone app that keeps a **Pulse One / Makina fitness band (model WS01A/BK)** useful
after its maker shut down. It talks to the band directly over Bluetooth, keeps your data on the
phone and writes it to **Apple Health**. No account, no cloud, no third-party services.

> Not affiliated with Pulse, Makina or the band's manufacturer. Not a medical device: the band's
> values (and especially its blood-pressure estimate) are for personal tracking only.

## Features

- **Sync from the band:** heart rate (spot checks and per-minute), HRV, blood oxygen, steps,
  distance, sleep stages and workouts, incrementally, with resume after a dropped connection.
- **Apple Health export:** automatic, at most hourly, or manually with "Export to Health now".
  Stable sync IDs, so nothing is duplicated; steps and distance per minute so Health's source
  priority works well next to your iPhone's own step counting. Samples show "Pulse One" as the device.
- **Background sync:** with the app closed (not force-quit) iOS wakes it a few times a day to sync
  from the band; Health export happens on those runs while the phone is unlocked. iOS decides the
  timing, and Background App Refresh must be on.
- **Today:** Fitness-style rings for sleep score, steps and the daily challenge, a day strip to look
  at any past day, highlights from your data ("resting heart rate 3 below your recent average"),
  an Oura-style sleep card (score, stages, night vitals), live heart rate with zones and
  measurements, and vitals tiles with sparklines. Sections can be reordered and hidden.
- **Readiness:** a morning score from last night's HRV and resting heart rate against your own
  baseline, your sleep score and yesterday's activity, with the main reason in one line.
- **Live Activity:** time, distance, pace and heart rate zone on the Lock Screen and in the Dynamic
  Island during a run, walk or ride, and the timer and reps during a timed challenge session.
- **Trends:** this week against last week for every metric, with highlights; detail screens with
  day / week / month / 6-month charts you can scrub.
- **Activities:** walks the band records on its own (and other workouts) appear on Today and go
  to Apple Health as workouts with active energy, steps, distance and average heart rate.
- **Start activity:** run, walk or ride with a target heart-rate zone. The phone's GPS records the
  route, distance and pace, the band supplies heart rate (and buzzes at the start); the result is
  saved with a map, splits and time in zones, and goes to Apple Health as a workout with its route.
  Optional zone alerts: the band buzzes 3 times after 15 s above the target zone and 2 times after
  15 s below (at most once a minute), also with the screen locked.
- **Daily challenge:** a daily goal like push-ups and squats. Log sets with +5 / +10 / +20 or a
  custom count, change targets any time (optionally +N every week), and follow streaks, a month
  calendar and totals. Share an image with your group; a timed session is saved to Apple Health as
  a Strength training workout with band heart rate.
- **Profile and zones:** age, sex, height and weight (shared with the band); max and resting heart
  rate come from your own data, and the five Karvonen zones update by themselves.
- **Live data on Today:** live heart rate on demand, on-demand HRV and heart-rate measurements,
  and today's steps following the band's live count while the app is open.
- **Band tab:** connection, battery with a 30-day history and daily use, sync, Apple Health export,
  pairing, and a diagnostics log (band traffic and sync events) you can export for bug reports.
- **Safe by design:** the commands that reset or wipe the band (`12`, `2E`, `61`, history delete
  mode `99`) can't be built by the code at all.

## How it works

The band speaks a JStyle-family protocol over a vendor service (`FFF0`), plus standard Bluetooth
services for live heart rate and battery. Everything learned while reverse engineering it is in
[docs/protocol.md](docs/protocol.md): framing, history records, paging, live data, sleep stage
mapping and the quirks found on real hardware.

The app is split into a tested Swift package and a thin iOS app:

| Folder | What it is |
|---|---|
| `PulseKit/` | Protocol, sync engine, local store (SwiftData), daily metrics, live feed, and the Bluetooth client (`PulseBLE`). Tested with `swift test`. |
| `PulseBridge/` | The SwiftUI app: Today, Trends, Challenge and Band tabs, HealthKit export. |
| `tools/ble-probe/` | Python (bleak) probe used to reverse engineer the band from a Mac. |
| `tools/pulse-sync/` | Mac command-line tool that runs the app's real sync engine against the band. |
| `docs/` | Protocol notes and the manual test checklist. |

## Build

Requirements: Xcode 26, an iPhone on iOS 18 or newer, and an Apple Developer account for signing.

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set your Team ID in it
xcodegen generate
open PulseBridge.xcodeproj                              # pick your iPhone and press Run
```

If the bundle ID `ro.codez.pulsebridge` isn't available in your account, set your own
`PRODUCT_BUNDLE_IDENTIFIER` in `Config/Local.xcconfig`.

`PulseBridge.xcodeproj` is generated from `project.yml` and not checked in: run `xcodegen generate`
again after pulling or after changing `project.yml`.

Tests and a simulator build need no band, no signing and no Team ID:

```bash
swift test --package-path PulseKit
xcodegen generate
xcodebuild -project PulseBridge.xcodeproj -scheme PulseBridge \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

CI runs the same on every push (`.github/workflows/ci.yml`).

## Tools (macOS, band nearby, phone app closed)

```bash
# Run the full sync against the band with a local test database (--help lists all options)
swift run --package-path tools/pulse-sync pulse-sync [--fresh] [--tz Area/City] [--disconnect-after SECONDS]

# Low-level probe (Python 3 + bleak)
cd tools/ble-probe && uv venv .venv && uv pip install --python .venv/bin/python -r requirements.txt
.venv/bin/python probe.py scan --match Pulse
.venv/bin/python probe.py dump
.venv/bin/python probe.py listen --seconds 20 --cmd 41
```

The band accepts one connection at a time, so close the iPhone app (or nRF Connect) first.

## Recommended Health setting

Health > Browse > Activity > Steps > Data Sources & Access > Edit: move Pulse Bridge above iPhone
(same for Walking + Running Distance). Health then uses the band's steps where both overlap and
the phone's steps when the band wasn't worn. On current iOS the Fitness app follows the same
priority; older versions of Fitness added both sources together.

## Use the band in Fitness workouts

The band is also a standard Bluetooth heart-rate monitor, so Apple's Fitness app can use it:

1. Close Pulse Bridge (swipe it away) so the band advertises.
2. Settings > Bluetooth: pair "Pulse One ...".
3. Fitness > Workout > Heart Rate Devices: the band is listed; start a workout. Heart rate appears
   after about 15 s.

Pulse Bridge keeps syncing alongside. Live zone training with buzzes on the band is only in Pulse
Bridge's Start activity; Fitness shows zones after the workout.

## Testing on a device

See [docs/TESTING.md](docs/TESTING.md) for the manual checklist, grouped by tab (pairing, Today, Trends, Challenge,
activities, Band, sync and Health export). Changes per version are in [CHANGELOG.md](CHANGELOG.md).

## License

MIT, see [LICENSE](LICENSE).
