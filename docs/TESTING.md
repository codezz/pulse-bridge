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

Order: status header, Sleep, Steps, Heart rate, Activities, Blood oxygen.

**Header**

4. The line under the title shows a green dot, battery and "Synced N min ago" (grey dot when not
   connected). During a sync: spinner and "Syncing...", then a success haptic. Tapping it opens the
   Band tab.
5. On launch, cards show grey placeholders for a moment, never "No data" before the data loaded.

**Sleep**

6. After a night with the band: score ring and label, time asleep, fell asleep and woke up times,
   a stage bar, resting HR and HRV. Without one: "No sleep data for last night".
7. Sleep detail D: score with 7 contributors, stage chart (Awake / REM / Core / Deep), stage times
   with typical ranges, timing (efficiency, time to fall asleep, awakenings), night heart-rate chart
   with the lowest point, resting HR and HRV rows that open their trends. The info button explains
   the score. Regularity shows "midpoint HH:MM · usual HH:MM" once 3 earlier nights exist.
8. Sleep detail W and M: stacked stage bars per night, averages (time asleep, score, fell asleep,
   woke up, bedtime consistency) and the resting HR trend.

**Steps**

9. Today's steps, % of the 10,000 goal, distance and steps per hour. With the app open and the band
   connected, the number follows the band's live total while you walk.
10. Steps detail: D shows steps per hour; W and M show daily totals with a dashed goal line and
   "Goal reached on N of M days".

**Heart rate**

11. Live off: latest stored reading, "today 54-118 · resting 58", today's readings from 00:00.
12. Tap Live: the button turns into a red pill, the chart eases to the last hour (stored readings
   faded), "Starting the sensor..." then the live number, a heart beating at that rate and the zone
   name. The line changes color with the zone. With Reduce Motion on, the heart stays still.
13. Take the band off for 2 minutes: "Not on wrist?". Walk out of range: "Not connected", the line
   breaks and continues after the reconnect. Tap the pill: back to today's chart.
14. HRV 75 s / Heart rate 30 s run inside the card (progress, Cancel), results inline with Done, a
   success haptic at the end. Tapping the headline or chart opens the Heart rate detail; tapping the
   buttons doesn't.
15. Pull down to sync while live is on: the sync completes and the live line continues.

**Activities**

16. The card shows the latest activity and the 7-day count; tapping it opens the list. A walk the band
   detected appears after a sync and in Health > Workouts after the next export.
17. Start opens a half-height sheet (Run / Walk / Ride, zones with bpm, warnings). Location denied:
   Start disabled with Open Settings; allowing it in Settings clears the warning.
18. Run, Zone 2 > Start: the sheet closes, a strong haptic, the band buzzes 3 times; the live screen
   shows time, distance, pace, heart rate (after about 15 s) with zone status. Lock the phone, run
   10+ minutes, unlock: still recording, heart rate included.
19. Finish > Save: summary with map, splits and zones; Health shows a Running workout with route and
   heart rate from Pulse Bridge. Band distance for that time span is not added to Health twice.
20. Finish > Discard asks for confirmation first.
21. Kill the app during an activity and reopen: "Unfinished activity" offers Save or Discard.
22. Zone 2 run with "Zone alerts on the band" on (bell on the live screen): after 15 s above the zone
   the band buzzes 3 times, after 15 s below 2 times (can you feel the 2? if not, report it), at most
   once a minute while outside; also with the screen locked. With the toggle off: no alerts.

**Blood oxygen**

23. The card shows the latest reading and today's range; detail D shows the day's readings (arrows move
   between days, next is disabled on today), W and M one value per day; "No data" without readings.

**Charts**

24. In every detail chart (HR / SpO2 day, steps per hour, W/M bars, night HR, sleep W/M, resting HR
   trend), press and drag: a rule and a bubble with value and time or day follow the finger, with a
   light tick per point. Scrolling the page over a chart still works.

## Band tab

25. Status "Connected", battery percentage, last sync and Health export as "N min ago".
26. Sync (or pull down on Summary): "Last sync" updates but "Health export" does not.
    "Export to Health now" writes what is queued without talking to the band.
27. Forget band asks for confirmation, then shows the pairing sheet.
28. Diagnostics: after a sync the size grows; Export log opens the share sheet with "sync started",
    sent/received hex lines and "sync finished: new ..."; the serial appears only as its last 2
    digits. Clear asks for confirmation, then empties it.
29. Battery card: "Collecting data" at first, a 30-day chart after a few connections, "About N% per
   day" after 2 days (charging doesn't lower it).
30. Background App Refresh off for Pulse Bridge: the Band card shows the hint to turn it on.

## Sync and Health

31. Health app: only data from after "Health data since" appears, from Pulse Bridge, at the right times.
32. Sync twice: the second adds nothing and Health shows no duplicates.
33. Walk out of range mid-sync: an error shows; come back and sync: it completes, nothing duplicated.
34. Deny Heart Rate in Settings > Health > Data Access > Pulse Bridge and wait for the hourly export:
    "Not allowed in Health: heartRate" shows. Allow it again: the queued samples reach Health.
35. Background the app: the band disconnects (unless an activity is running). Reopen within the hour: it only reconnects. Reopen after
    an hour: a sync with Health export runs by itself.
36. Sync after more than 3 days without syncing: every type completes (multi-page read).
37. Sync during a walk, sync again 10 minutes later: the later minutes of that block reach Health.
38. Change the phone's time zone and sync: the band shows the new local time and no data is missing.
39. Background sync: leave the app in the background (don't force-quit) with the band nearby for a
   few hours: "Background sync" on the Band card shows a time and new data is in Health (if the
   phone was unlocked at that moment). Diagnostics shows "background sync started".
40. Band away during a background run: diagnostics shows "band not in range"; opening the app later
   syncs right away.
41. Health > Steps or Walking + Running Distance > Show All Data: a new sample shows device
   "Pulse One"; distance samples are one minute long.
42. Fitness workout with the band paired in Settings > Bluetooth: heart rate shows in the workout;
   Pulse Bridge still syncs afterwards.
