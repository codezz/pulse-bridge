# Manual test checklist (real iPhone + band)

Close nRF Connect, the Mac tools and any other app connected to the band first: it accepts one
connection at a time.

## First launch and pairing

1. Bluetooth prompt appears; allow it. The pairing sheet lists "Pulse One ...". Tap it.
2. A sync starts by itself. The Health permission sheet appears; allow all. The first sync reads the
   band's whole history (can take a minute) and sets "Health data since" to now: older history stays
   on the phone and is not written to Health.
3. Band > Profile and zones is pre-filled from the band (age, sex, height, weight).

## Today tab

Tabs: Today, Trends, Challenge, Band. Today: status line, day strip, rings, then the sections in the
order set in Edit Today (default: Highlights, Sleep, Heart rate, Vitals, Daily challenge, Activities).

**Readiness**

4. Readiness (near the top of Today): after 5+ nights with the band, a score ring, label, the main
   reason ("HRV 10% below your usual", "You're recovered") and bars for HRV, resting heart rate,
   sleep and activity; with fewer nights "Calibrating: N more nights". Tapping opens the detail with
   each contributor's value against your usual and the last 14 days. A past day shows that day.

**Header**

5. The line under the title shows a green dot, battery and "Synced N min ago" (grey dot when not
   connected). During a sync: spinner and "Syncing...", then a success haptic. Tapping it opens the
   Band tab.
6. On launch, cards show grey placeholders for a moment, never "No data" before the data loaded.

**Day strip, rings, highlights**

7. The day strip shows this week (Monday first) with tiny rings per day; chevrons move by week, the
   next week is disabled while it contains today, future days are dimmed. Tapping a past day shows
   that day everywhere: the title becomes the date, a Today button returns.
8. On a past day: no live heart rate and no HRV / HR buttons (the day's stored readings instead); the
   challenge card shows that day's rings and "Done" / "Partly done" / "Nothing logged" without Log.
9. Rings: Sleep score, Steps (of 10,000), Challenge, with one line each. Reaching 10,000 steps or
   finishing the challenge for today while the screen is open: a sparkle burst and a success haptic
   (once, not on every open). Over 100% steps draws a second, darker lap.
10. Highlights: up to 3 lines like "Resting heart rate 56 bpm, 3 below your recent average" with a
   green (better) or orange (worse) arrow; tapping opens the metric. With little data: "Nothing
   stands out yet".
11. Edit Today: switch sections off and drag to reorder; the order stays after relaunching.

**Sleep**

12. After a night with the band: score ring and label, time asleep, fell asleep and woke up times,
   a stage bar, resting HR and HRV. Without one: "No sleep data for last night".
13. Sleep detail D: score with 7 contributors, stage chart (Awake / REM / Core / Deep), stage times
   with typical ranges, timing (efficiency, time to fall asleep, awakenings), night heart-rate chart
   with the lowest point, resting HR and HRV rows that open their trends. The info button explains
   the score. Regularity shows "midpoint HH:MM · usual HH:MM" once 3 earlier nights exist.
14. Sleep detail W and M: stacked stage bars per night, averages (time asleep, score, fell asleep,
   woke up, bedtime consistency) and the resting HR trend.

**Vitals and steps**

15. Vitals tiles: Resting HR and HRV (last night, 14-night sparkline), Blood oxygen (latest, today's
   readings), Steps (today, steps per hour). Steps follow the band's live total while connected.
   Tapping a tile opens its detail on that day.
16. Steps detail: D shows steps per hour; W and M show daily totals with a dashed goal line and
   "Goal reached on N of M days"; 6M shows weekly averages. Every detail shows a big average, the
   range under it and the metric's highlight on top when there is one.

**Heart rate**

17. Live off: latest stored reading, "today 54-118 · resting 58", today's readings from 00:00.
18. Tap Live: the button turns into a red pill, the chart eases to the last hour (stored readings
   faded), "Starting the sensor..." then the live number, a heart beating at that rate and the zone
   name. The line changes color with the zone. With Reduce Motion on, the heart stays still.
19. Take the band off for 2 minutes: "Not on wrist?". Walk out of range: "Not connected", the line
   breaks and continues after the reconnect. Tap the pill: back to today's chart.
20. HRV 75 s / Heart rate 30 s run inside the card (progress, Cancel), results inline with Done, a
   success haptic at the end. Tapping the headline or chart opens the Heart rate detail; tapping the
   buttons doesn't.
21. Pull down to sync while live is on: the sync completes and the live line continues.

**Activities**

22. The card shows the latest activity and the 7-day count; tapping it opens the list (GPS activities
   with a route thumbnail, distance, time and pace). A walk the band
   detected appears after a sync and in Health > Workouts after the next export.
23. Start opens a half-height sheet (Run / Walk / Ride, zones with bpm, warnings). Location denied:
   Start disabled with Open Settings; allowing it in Settings clears the warning.
24. Run, Zone 2 > Start: the sheet closes, a strong haptic, the band buzzes 3 times; the live screen
   shows time, distance, pace, heart rate (after about 15 s); swipe for the heart-rate page (zone,
   time in target) and splits, the Pause / Finish buttons stay at the bottom. Lock the phone: the Lock
   Screen and the Dynamic Island show the running time, distance, pace and heart rate with zone status
   (updated about every 5 s); Pause freezes the time there right away. After Finish the final numbers
   stay for 15 minutes. A timed challenge session shows its timer, heart rate and reps the same way. Lock the phone, run
   10+ minutes, unlock: still recording, heart rate included.
25. Finish > Save: summary with map, splits and zones; Health shows a Running workout with route and
   heart rate from Pulse Bridge. Band distance for that time span is not added to Health twice.
26. Finish > Discard asks for confirmation first.
27. Kill the app during an activity and reopen: "Unfinished activity" offers Save or Discard.
28. Zone 2 run with "Zone alerts on the band" on (bell on the live screen): after 15 s above the zone
   the band buzzes 3 times, after 15 s below 2 times (can you feel the 2? if not, report it), at most
   once a minute while outside; also with the screen locked. With the toggle off: no alerts.

**Blood oxygen**

29. The Blood oxygen tile shows the latest reading and today's range; detail D shows the day's readings (arrows move
   between days, next is disabled on today), W and M one value per day; "No data" without readings.

**Charts**

30. In every detail chart (HR / SpO2 day, steps per hour, W/M bars, night HR, sleep W/M, resting HR
   trend), press and drag: a rule and a bubble with value and time or day follow the finger, with a
   light tick per point. Scrolling the page over a chart still works.

## Trends tab

31. Highlights (all of them), then a card per metric (time asleep, steps, resting HR, HRV, heart rate,
   blood oxygen): this week's average, the change against last week with a green or orange arrow,
   and a 30-day sparkline; "Not enough data yet" with fewer than 4 days in either week. Tapping
   opens the detail.

## Challenge tab

32. Before setup the Challenge tab and the Today card offer "Set up challenge"; setup is pre-filled with Push-ups 60 and Squats 60
   (reps). Start: the tab shows a ring per exercise at 0/60 and "Start a streak today".
33. In the tab (or Log sets on the Today card, which opens it): +5 / +10 / +20 and Custom add sets; the ring and the big number update with a light tap
   haptic; Undo last removes the latest set of that exercise today (disabled when there is none).
   Reaching both targets: a success haptic and "Done for today" on the card.
34. Exercises (gear): change a target; the card uses it today, the calendar shows earlier days with the old
   target. Turn on "+5 every Monday": the target grows from next Monday, not today. Add an exercise
   (reps or seconds); archive one (confirmation): it leaves the card and logger, its history stays.
35. Below the logging: current and best streak (an unfinished today doesn't break the streak), month calendar
   (green done, light partial, gray nothing, today ringed, previous/next month), tap a day for its
   sets and targets; a card per exercise with totals and the last 14 days against the target.
36. Exercises > Progress before the app: enter start date, days done, streak and best (e.g. 27 Aug,
   33, 1, 14). The tab shows "🔥 2 day streak, best 14 · 34 days done of 39"; days between the start
   and your first day in the app have a dashed ring and can't be opened; earlier days are plain.
   With an average per day entered (e.g. 50), each exercise's all-time total includes 33 x 50.
   Top row: streak (best), days done (of day number), % of days hit. Each exercise has a card:
   all-time total, bars for the last 14 days (full color when the target was hit) with the target as
   a dashed line, and Week / Month / Avg/day.
37. Share: the share button opens the share sheet with an image of today's numbers, the streak and the
   last 7 days.
38. Timed session: Start timed session shows a timer and band heart rate; log sets; Finish session:
   Health shows a Strength training workout from Pulse Bridge with that duration and heart rate.
   Lock the phone for a few minutes during the session: heart rate keeps coming (no gap in Health).
   Cancel session keeps the sets but saves nothing to Health. Live heart rate on the Heart rate card
   keeps running when a session ends. Kill the app mid-session and reopen: the session is saved up
   to its last set and reaches Health with the next sync.

## Band tab

39. Top: "Pulse One" with a green dot and "Connected", battery ring. Sync card: last sync, Health
   export and background sync as "N min ago". Forget band is the last button.
40. Sync (or pull down on Today): "Last sync" updates but "Health export" does not.
    "Export to Health now" writes what is queued without talking to the band.
41. Forget band asks for confirmation, then shows the pairing sheet.
42. Diagnostics: after a sync the size grows; Export log opens the share sheet with "sync started",
    sent/received hex lines and "sync finished: new ..."; the serial appears only as its last 2
    digits. Clear asks for confirmation, then empties it.
43. Battery card: "Collecting data" at first, a 30-day chart after a few connections, "About N% per
   day" after 2 days (charging doesn't lower it).
44. Background App Refresh off for Pulse Bridge: the Band card shows the hint to turn it on.

## Sync and Health

45. Health app: only data from after "Health data since" appears, from Pulse Bridge, at the right times.
46. Sync twice: the second adds nothing and Health shows no duplicates.
47. Walk out of range mid-sync: an error shows; come back and sync: it completes, nothing duplicated.
48. Deny Heart Rate in Settings > Health > Data Access > Pulse Bridge and wait for the hourly export:
    "Not allowed in Health: heartRate" shows. Allow it again: the queued samples reach Health.
49. Background the app: the band disconnects (unless an activity is running). Reopen within the hour: it only reconnects. Reopen after
    an hour: a sync with Health export runs by itself.
50. Sync after more than 3 days without syncing: every type completes (multi-page read).
51. Sync during a walk, sync again 10 minutes later: the later minutes of that block reach Health.
52. Change the phone's time zone and sync: the band shows the new local time and no data is missing.
53. Background sync: leave the app in the background (don't force-quit) with the band nearby for a
   few hours: "Background sync" on the Band card shows a time and new data is in Health (if the
   phone was unlocked at that moment). Diagnostics shows "background sync started".
54. Band away during a background run: diagnostics shows "band not in range"; opening the app later
   syncs right away.
55. Health > Steps or Walking + Running Distance > Show All Data: a new sample shows device
   "Pulse One"; distance samples are one minute long.
56. Fitness workout with the band paired in Settings > Bluetooth: heart rate shows in the workout;
   Pulse Bridge still syncs afterwards.
