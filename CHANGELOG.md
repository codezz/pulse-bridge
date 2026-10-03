# Changelog

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
