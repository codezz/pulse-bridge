# Changelog

## Unreleased

- **Romanian:** the whole app, the Live Activity and the permission prompts, following the phone's
  language or Settings > Pulse Bridge > Language. Apple Health data and the diagnostics log stay
  in English.
- **Challenge share as text:** two short lines in the app's language instead of an image, e.g.
  "💪 Ziua 37/42. 5 zile la rând" and "✅ 60F/60G" (count and first letter per exercise). The share
  language can differ from the app's (Challenge > Exercises > Share in).
- At large text sizes, Vitals tile titles wrap and the Band tab's Sync / Open Health buttons stack.

## 0.2.0 (2026-10-05)

- **New design:** four tabs (Today, Trends, Challenge, Band) with Health-style cards, rings and
  tiles. Today has a week strip to open any past day, hero rings (sleep, steps, challenge),
  highlights, vitals tiles and sections you can hide and reorder (Edit Today).
- **Readiness score** each morning from HRV, resting heart rate, sleep, activity and temperature
  against your own 30-night baseline, with the reason and a 14-day chart.
- **Trends:** highlights, this week against last week for every metric, 6-month charts.
- **Temperature** from the band: night average against your usual, in Vitals, Trends and readiness
  (not written to Health).
- **Estimated wake-ups** on the sleep detail, from heart-rate rises and stage changes (shown only).
- **Daily challenge:** exercises with targets that can grow every week, sets with undo, streaks,
  calendar, totals, progress from before the app, a share image, and timed sessions saved to Health
  as Strength training.
- **Live Activity** on the Lock Screen and in the Dynamic Island during an activity or a timed
  session.
- **Heart rate card** with the live last hour, zones and inline HRV and heart-rate measurements;
  press and drag on charts to read values.
- **Zone alerts:** the band buzzes 3 times above the target zone and 2 times below.
- **Background sync** a few times a day while the app is in the background.
- **Battery history** with the average daily use.
- Health samples name Pulse One as the device; distance is written per minute.
- Daily totals are no longer read (the activity records hold the same steps and distance).
- Delete modes are refused for every history, alarm and temperature command.

## 0.1.0 (2026-10-03)

First public version.

- **Sync** from the Pulse One band over Bluetooth: heart rate (spot and per minute), HRV, blood
  oxygen, steps, distance, sleep stages and workouts. Incremental, resumes after a dropped
  connection, sets the band clock on every sync.
- **Apple Health export**, automatic at most hourly or manual ("Export to Health now"), with stable
  sync IDs (no duplicates) and a "Health data since" date so old history stays on the phone.
- **Summary:** Oura-style sleep score (evidence-based contributors), stages and night vitals; steps
  toward a 10,000 goal; heart rate and blood oxygen with day / week / month charts; live heart rate
  and on-demand HRV and heart-rate measurements.
- **Activities:** walks the band detects are shown and exported as workouts. Start a run, walk or
  ride with phone GPS, band heart rate and Karvonen zones; saved with map, splits and time in zones,
  and exported to Health as a workout with its route.
- **Band tab:** connection, battery, sync, profile and zones, and an exportable diagnostics log.
- Commands that reset or wipe the band can't be built by the code.

Review fixes before release: repeated clock hours and records re-read in another clock offset are
kept correctly, corrupt records are skipped, the band clock offset is saved even when a sync fails,
GPS activities hold back the band's overlapping distance and heart rate, faster Summary loads, and
confirmation before discarding an activity, forgetting the band or clearing the log.
