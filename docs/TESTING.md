# Manual test checklist (real iPhone + band)

Close nRF Connect, the Mac tools and any other app connected to the band first: it accepts one
connection at a time.

## First launch and pairing

1. Bluetooth prompt appears; allow it. The pairing sheet lists "Pulse One ...". Tap it.
2. A sync starts by itself. The Health permission sheet appears; allow all. The first sync reads the
   band's whole history (can take a minute) and sets "Health data since" to now: older history stays
   on the phone and is not written to Health.
3. Band > Profile and zones is pre-filled from the band (age, sex, height, weight).

## Summary tab

Order: Sleep, Steps, Activities, Heart rate, Live heart rate, Measure now, Start activity, Blood oxygen.

**Sleep**

4. After a night with the band: score ring and label, time asleep, fell asleep and woke up times,
   a stage bar, resting HR and HRV. Without one: "No sleep data for last night".
5. Sleep detail D: score with 7 contributors, stage chart (Awake / REM / Core / Deep), stage times
   with typical ranges, timing (efficiency, time to fall asleep, awakenings), night heart-rate chart
   with the lowest point, resting HR and HRV rows that open their trends. The info button explains
   the score. Regularity shows "midpoint HH:MM · usual HH:MM" once 3 earlier nights exist.
6. Sleep detail W and M: stacked stage bars per night, averages (time asleep, score, fell asleep,
   woke up, bedtime consistency) and the resting HR trend.

**Steps**

7. Today's steps, % of the 10,000 goal, distance and steps per hour. With the app open and the band
   connected, the number follows the band's live total while you walk.
8. Steps detail: D shows steps per hour; W and M show daily totals with a dashed goal line and
   "Goal reached on N of M days".

**Activities**

9. Walk continuously for 10+ minutes with the band, then sync: a new Walk appears on the card and in
   the list (duration, steps, distance, pace, avg HR, kcal). After the next Health export it shows in
   Health > Workouts as a Walk from Pulse Bridge.

**Heart rate and blood oxygen**

10. Cards show the latest reading and today's range with today's readings charted. Detail D shows the
    day's readings (arrows move between days, next is disabled on today); W and M one value per day.
    Days without data show "No data".

**Live heart rate and Measure now**

11. Start live heart rate: "Starting the sensor..." for about 10 s, then readings every second and a
    growing chart. Stop hides it. Take the band off: after about 2 minutes "Not on wrist?" appears.
12. Measure HRV: the progress bar runs about 75 s, then HRV, HR, stress and a BP estimate show. After
    the next sync the HRV value is in Health.
13. Pull down to sync while live heart rate runs: the sync completes and the live data resumes.

**Start activity**

14. Location denied: Start is disabled with "Allow location..." and an Open Settings button. Allow it
    in Settings and come back: the warning goes away without reopening the app.
15. Run, Zone 2 > Start: the band buzzes 3 times; the live screen shows time, distance, pace, heart
    rate (after about 15 s) with zone status. Lock the phone, run 10+ minutes, unlock: still
    recording, heart rate included.
16. Finish > Save: summary with map, splits and zones; Health shows a Running workout with route and
    heart rate from Pulse Bridge. Band distance for that time span is not added to Health twice.
17. Finish > Discard asks for confirmation first.
18. Kill the app during an activity and reopen: "Unfinished activity" offers Save or Discard.

## Band tab

19. Status "Connected", battery percentage, last sync and Health export times.
20. Sync (or pull down on Summary): "Last sync" updates but "Health export" does not.
    "Export to Health now" writes what is queued without talking to the band.
21. Forget band asks for confirmation, then shows the pairing sheet.
22. Diagnostics: after a sync the size grows; Export log opens the share sheet with "sync started",
    sent/received hex lines and "sync finished: new ..."; the serial appears only as its last 2
    digits. Clear asks for confirmation, then empties it.

## Sync and Health

23. Health app: only data from after "Health data since" appears, from Pulse Bridge, at the right times.
24. Sync twice: the second adds nothing and Health shows no duplicates.
25. Walk out of range mid-sync: an error shows; come back and sync: it completes, nothing duplicated.
26. Deny Heart Rate in Settings > Health > Data Access > Pulse Bridge and wait for the hourly export:
    "Not allowed in Health: heartRate" shows. Allow it again: the queued samples reach Health.
27. Background the app: the band disconnects. Reopen within the hour: it only reconnects. Reopen after
    an hour: a sync with Health export runs by itself.
28. Sync after more than 3 days without syncing: every type completes (multi-page read).
29. Sync during a walk, sync again 10 minutes later: the later minutes of that block reach Health.
30. Change the phone's time zone and sync: the band shows the new local time and no data is missing.
