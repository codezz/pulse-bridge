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
   sleep, activity and temperature; with fewer nights "Calibrating: N more nights". Tapping opens the detail with
   each contributor's value against your usual and the last 14 days. A past day shows that day.

**Temperature and wake-ups**

5. Vitals: Resting HR, HRV, Blood oxygen and Temperature tiles (Temperature: last night's average, 14-night sparkline), Steps full width under them; temperature W/M is a line with points. Sleep detail D: Night
   vitals shows "36.4 °C · +0.3 vs usual" (the "vs usual" part after 5 nights), Timing shows
   "Wake-ups (estimated)" with times and reasons, and orange triangles mark them on the night's
   heart-rate chart. Trends has a Temperature row; a night 0.3 °C or more above usual is a
   highlight and lowers readiness.

**Header**

6. The line under the title shows a green dot, battery and "Synced N min ago" (grey dot when not
   connected). During a sync: spinner and "Syncing...", then a success haptic. Tapping it opens the
   Band tab.
7. On launch, cards show grey placeholders for a moment, never "No data" before the data loaded.

**Day strip, rings, highlights**

8. The day strip shows this week (Monday first) with tiny rings per day; chevrons move by week, the
   next week is disabled while it contains today, future days are dimmed. Tapping a past day shows
   that day everywhere: the title becomes the date, a Today button returns.
9. On a past day: no live heart rate and no HRV / HR buttons (the day's stored readings instead); the
   challenge card shows that day's rings and "Done" / "Partly done" / "Nothing logged" without Log.
10. Rings: Sleep score, Steps (of 10,000), Challenge, with one line each. Reaching 10,000 steps or
   finishing the challenge for today while the screen is open: a sparkle burst and a success haptic
   (once, not on every open). Over 100% steps draws a second, darker lap.
11. Highlights: up to 3 lines like "Resting heart rate 56 bpm, 3 below your recent average" with a
   green (better) or orange (worse) arrow; tapping opens the metric. With little data: "Nothing
   stands out yet".
12. Edit Today: switch sections off and drag to reorder; the order stays after relaunching.

**Sleep**

13. After a night with the band: score ring and label, time asleep, fell asleep and woke up times,
   a stage bar, resting HR and HRV. Without one: "No sleep data for last night".
14. Sleep detail D: score with 7 contributors, stage chart (Awake / REM / Core / Deep), stage times
   with typical ranges, timing (efficiency, time to fall asleep, awakenings), night heart-rate chart
   with the lowest point, resting HR and HRV rows that open their trends. The info button explains
   the score. Regularity shows "midpoint HH:MM · usual HH:MM" once 3 earlier nights exist.
15. Sleep detail W and M: stacked stage bars per night, averages (time asleep, score, fell asleep,
   woke up, bedtime consistency) and the resting HR trend.

**Vitals and steps**

16. Vitals tiles: Resting HR and HRV (last night, 14-night sparkline), Blood oxygen (latest, today's
   readings), Steps (today, steps per hour). Steps follow the band's live total while connected.
   Tapping a tile opens its detail on that day.
17. Steps detail: D shows steps per hour; W and M show daily totals with a dashed goal line and
   "Goal reached on N of M days"; 6M shows weekly averages. Every detail shows a big average, the
   range under it and the metric's highlight on top when there is one.

**Heart rate**

18. Live off: latest stored reading, "today 54-118 · resting 58", today's readings from 00:00.
19. Tap Live: the button turns into a red pill, the chart eases to the last hour (stored readings
   faded), "Starting the sensor..." then the live number, a heart beating at that rate and the zone
   name. The line changes color with the zone. With Reduce Motion on, the heart stays still.
20. Take the band off for 2 minutes: "Not on wrist?". Walk out of range: "Not connected", the line
   breaks and continues after the reconnect. Tap the pill: back to today's chart.
21. HRV 75 s / Heart rate 30 s run inside the card (progress, Cancel), results inline with Done, a
   success haptic at the end. Tapping the headline or chart opens the Heart rate detail; tapping the
   buttons doesn't.
22. Pull down to sync while live is on: the sync completes and the live line continues.

**Activities**

23. The card shows the latest activity and the 7-day count; tapping it opens the list (GPS activities
   with a route thumbnail, distance, time and pace). A walk the band
   detected appears after a sync and in Health > Workouts after the next export.
24. Start opens a half-height sheet (Run / Walk / Ride, zones with bpm, warnings). Location denied:
   Start disabled with Open Settings; allowing it in Settings clears the warning.
25. Run, Zone 2 > Start: the sheet closes, a strong haptic, the band buzzes 3 times; the live screen
   shows time, distance, pace, heart rate (after about 15 s); swipe for the heart-rate page (zone,
   time in target) and splits, the Pause / Finish buttons stay at the bottom. Lock the phone: the Lock
   Screen and the Dynamic Island show the running time, distance, pace and heart rate with zone status
   (updated about every 5 s); Pause freezes the time there right away. After Finish the final numbers
   stay for 15 minutes. A timed challenge session shows its timer, heart rate and reps the same way. Lock the phone, run
   10+ minutes, unlock: still recording, heart rate included.
26. Finish > Save: summary with map, splits and zones; Health shows a Running workout with route and
   heart rate from Pulse Bridge. Band distance for that time span is not added to Health twice.
27. Finish > Discard asks for confirmation first.
28. Kill the app during an activity and reopen: "Unfinished activity" offers Save or Discard.
29. Zone 2 run with "Zone alerts on the band" on (bell on the live screen): after 15 s above the zone
   the band buzzes 3 times, after 15 s below 2 times (can you feel the 2? if not, report it), at most
   once a minute while outside; also with the screen locked. With the toggle off: no alerts.

**Blood oxygen**

30. The Blood oxygen tile shows the latest reading and today's range; detail D shows the day's readings (arrows move
   between days, next is disabled on today), W and M one value per day; "No data" without readings.

**Charts**

31. In every detail chart (HR / SpO2 day, steps per hour, W/M bars, night HR, sleep W/M, resting HR
   trend), press and drag: a rule and a bubble with value and time or day follow the finger, with a
   light tick per point. Scrolling the page over a chart still works.

## Trends tab

32. Highlights (all of them), then a card per metric (time asleep, steps, resting HR, HRV, heart rate,
   blood oxygen): this week's average, the change against last week with a green or orange arrow,
   and a 30-day sparkline; "Not enough data yet" with fewer than 4 days in either week. Tapping
   opens the detail.

## Challenge tab

33. Before setup the Challenge tab and the Today card offer "Set up challenge"; setup is pre-filled with Push-ups 60 and Squats 60
   (reps). Start: the tab shows a row per exercise at 0/60.
34. In the tab (or Log sets on the Today card, which opens it), the Today card has a stats line
   (streak and best, days done of day number, % hit) and one row per exercise: a small ring,
   "40/60 reps", +5 / +10 / +20 and a ⋯ menu (Custom amount, Undo last set). Each set gives a light
   tap haptic and a "+10 Push-ups · Undo" banner at the bottom for 4 seconds. A finished exercise
   turns green and keeps only the ⋯ menu (with Add 5 / 10 / 20). Finishing both: a sparkle burst
   and a success haptic. With the largest text sizes the stats and buttons wrap to extra lines, never
   cut off.
35. Exercises (gear): change a target; the card uses it today, the calendar shows earlier days with the old
   target. Turn on "+5 every Monday": the target grows from next Monday, not today. Add an exercise
   (reps or seconds); archive one (confirmation): it leaves the card and logger, its history stays.
36. Calendar card: this week as small rings (how much of the targets was done, green when done,
   today's number in orange); "Show month" expands to the month with arrows, "Show week" folds it.
   Tap a day for its sets and targets. Totals card: one row per exercise (this week, last 7 days as
   bars, all-time total); tapping opens the last 14 days against the dashed target line and All time
   / Week / Month / Avg/day.
37. Exercises > Progress before the app: enter start date, days done, streak and best (e.g. 27 Aug,
   33, 1, 14). The stats line shows "2 best 14 · 34 of 39 days"; days between the start
   and your first day in the app have a dashed ring and can't be opened; earlier days are plain.
   With an average per day entered (e.g. 50), each exercise's all-time total includes 33 x 50.
   The stats line shows streak (best), days done (of day number) and % of days hit.
38. Share: the share button opens the share sheet with two lines, e.g. in Romanian
   "💪 Ziua 37/42. 5 zile la rând" (days done / day number, then the streak, left out at 0) and
   "✅ 60F/60G" (each exercise's count and first letter; ⏳ until every target is reached). In English:
   "💪 Day 37/42. 5-day streak". Exercises (gear) > Share in: Română shares the Romanian text while
   the app stays in English (and English the other way round); App language follows the app.
   Exercises named Push-ups / Squats share as F / G in Romanian (and Flotări / Genuflexiuni as
   P / S in English); other names keep their own first letter.
39. Timed session: Start timed session (its note says "No band: no heart rate" when not connected)
   pins a bar at the bottom with the timer and band heart rate; log sets; Finish:
   Health shows a Strength training workout from Pulse Bridge with that duration and heart rate.
   Lock the phone for a few minutes during the session: heart rate keeps coming (no gap in Health).
   Cancel session (in the bar's ⋯ menu) keeps the sets but saves nothing to Health. Live heart rate on the Heart rate card
   keeps running when a session ends. Kill the app mid-session and reopen: the session is saved up
   to its last set and reaches Health with the next sync.

## Band tab

40. Top: "Pulse One" with a green dot and "Connected", battery ring. Sync card: last sync, Health
   export and background sync as "N min ago". Forget band is the last button.
41. Sync (or pull down on Today): "Last sync" updates but "Health export" does not.
    "Export to Health now" writes what is queued without talking to the band.
42. Forget band asks for confirmation, then shows the pairing sheet.
43. Diagnostics: after a sync the size grows; Export log opens the share sheet with "sync started",
    sent/received hex lines and "sync finished: new ..."; the serial appears only as its last 2
    digits. Clear asks for confirmation, then empties it.
44. Battery card: "Collecting data" at first, a 30-day chart after a few connections, "About N% per
   day" after 2 days (charging doesn't lower it).
45. Background App Refresh off for Pulse Bridge: the Band card shows the hint to turn it on.

## Sync and Health

46. Health app: only data from after "Health data since" appears, from Pulse Bridge, at the right times.
47. Sync twice: the second adds nothing and Health shows no duplicates.
48. Walk out of range mid-sync: an error shows; come back and sync: it completes, nothing duplicated.
49. Deny Heart Rate in Settings > Health > Data Access > Pulse Bridge and wait for the hourly export:
    "Not allowed in Health: heartRate" shows. Allow it again: the queued samples reach Health.
50. Background the app: the band disconnects (unless an activity is running). Reopen within the hour: it only reconnects. Reopen after
    an hour: a sync with Health export runs by itself.
51. Sync after more than 3 days without syncing: every type completes (multi-page read).
52. Sync during a walk, sync again 10 minutes later: the later minutes of that block reach Health.
53. Change the phone's time zone and sync: the band shows the new local time and no data is missing.
54. Background sync: leave the app in the background (don't force-quit) with the band nearby for a
   few hours: "Background sync" on the Band card shows a time and new data is in Health (if the
   phone was unlocked at that moment). Diagnostics shows "background sync started".
55. Band away during a background run: diagnostics shows "band not in range"; opening the app later
   syncs right away.
56. Health > Steps or Walking + Running Distance > Show All Data: a new sample shows device
   "Pulse One"; distance samples are one minute long.
57. Fitness workout with the band paired in Settings > Bluetooth: heart rate shows in the workout;
   Pulse Bridge still syncs afterwards.

## Language

58. Settings > Pulse Bridge > Language > Română (or the phone in Romanian): every tab, detail, alert,
   the highlights, readiness reasons, sleep labels, "Sincronizat acum N min" and the Live Activity are
   in Romanian; numbers and dates use Romanian formatting; plurals read right ("1 zi", "6 zile",
   "20 de zile"). The first Bluetooth, Health and Location prompts are in Romanian too.
59. In Romanian, sync and export: Health samples still show the device "Pulse One"; a challenge
   session's workout is a Strength training workout as before. Band > Diagnostics > Export log
   stays in English.
60. Largest text sizes in Romanian: titles and buttons wrap or stack (Vitals tiles, Sync / Open
   Health), nothing is cut off with "...".
61. New challenge setup in Romanian suggests "Flotări" and "Genuflexiuni"; exercises you already
   named keep their names.
