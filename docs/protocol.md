# Pulse One (WS01A/BK) BLE protocol

Reverse engineered 2026-10-02 with `tools/ble-probe` (macOS, CoreBluetooth via bleak).
Raw captures stay local (`logs/` is gitignored: they contain personal health data).

## Device

| Field | Value |
|---|---|
| Advertised name | `Pulse One NNNN` (last digits of the serial) |
| Manufacturer data | company `0x1234`: MAC (6 bytes) + serial ASCII `WS01A-01-NNNNNNc` |
| Model / serial | `WS01A/BK` / `WS01A-01-NNNNN` |
| Firmware | `V_31303137-251118` (1.0.1.7, built 2025-11-18) |
| MAC | 6 bytes, also in the manufacturer data |
| MTU | 247 |

Protocol family: **JStyle** (same vendor as JCVitalPro).

## GATT

| Service | Characteristic | Props | Use |
|---|---|---|---|
| `180D` Heart Rate | `2A37` | notify | live HR, 1 Hz |
| `1822` Pulse Oximeter | `2A5F` | notify | live SpO2 (no data seen passively) |
| `180F` Battery | `2A19` | read, notify | battery % |
| `1814` RSC | `2A53` | notify | cadence (no data seen passively) |
| `180A` Device Info | `2A29/24/25/27/26` | read | strings above |
| `FFF0` vendor | `FFF6` | write, write-no-resp | commands |
| `FFF0` vendor | `FFF7` | notify | responses |

### Live HR (`2A37`)
Standard Bluetooth HR Measurement. Observed `00 3c` → flags `00` (uint8 bpm) → 60 bpm.

## Command channel (`FFF6` → `FFF7`)

**Frame:** 16 bytes. `[opcode, payload..., zero padding] + checksum`, checksum = `sum(bytes[0..14]) & 0xFF`.
Responses use the same opcode in byte 0. Long responses are streamed as concatenated records
(packets up to 240 bytes; records can span packets).

**Dates/times are BCD:** `26 03 27` = 2026-03-27, `05 09 03` = 05:09:03.

**History read modes (byte 1 of the command):**
- `00` read from newest
- `02` continue (next page; the band sends 500 records per page)
- `99` delete (NOT tested, avoid)

**End of data:** response `<opcode> ff` (seen when there's no data at all). A full page with no end marker means more pages are available.

**History records:** `[opcode, idx_lo, idx_hi, date(3 BCD), time(3 BCD), ...]`, newest first, `idx` is little-endian.

### Opcodes

| Op | Name | Response (after header) | Confidence |
|---|---|---|---|
| `41` | get time | `YY MM DD hh mm ss weekday` BCD (weekday 0=Sun, computed by band), then `f4`? | high |
| `01` | set time | send `01 YY MM DD hh mm ss` BCD, ack `01 f4`. Verified 2026-10-02 | high |
| `13` | battery | `pct`, then `00 43 40` (unknown) | high |
| `27` | version | `01 00 01 07` + build date BCD `25 11 18` | high |
| `22` | MAC | 6 bytes | high |
| `51` | daily totals | 27 B/rec: `51 idx date(3)` `steps u32` `kcal×10 u32` `dist×10m u32` `? u32` `? u8` `? u8` + pad | steps/dist high, kcal medium |
| `52` | activity detail | 25 B/rec: `52 idx(2) date(3) time(3)` `steps u16` `? u16` `dist×10m u16` `steps per minute ×10 (u8)` | high (sum of minutes = total) |
| `53` | sleep | 130 B/rec: `53 idx(2) date(3) time(3) count u8` + `count` per-minute stages (1..5), 2 h chunks | structure high, stage meaning unknown |
| `54` | dynamic HR | 24 B/rec: `54 idx(2) date(3) time(3)` + 15 per-minute bpm (`00` = none) | high |
| `55` | static HR | 10 B/rec: `55 idx(2) date(3) time(3) bpm` (`00` = failed) | high |
| `56` | HRV | 15 B/rec: `56 idx(2) date(3) time(3) hrv ? hr stress sys dia` | medium (values plausible against the SDK parser) |
| `66` | SpO2 | 10 B/rec: `66 idx(2) date(3) time(3) spo2` (e.g. `62` = 98%) | high |
| `65` | temperature | 11 B/rec: `65 idx(2) date(3) time(3) temp×10 u16 LE`, every 10 min (e.g. `66 01` = 35.8 °C; SDK "axillary temperature"; `62` answers `62 ff`) | high (verified 2026-10-05) |
| `60` | (SpO2 alt) | `60 ff`: not supported / empty | |
| `62` | temperature | `62 ff`: not supported | |
| `16` | button / photo-mode events from band | `16 07 01`, `16 08 00`, `16 09 02` | medium (SDK) |

**Never send:** `12` (factory reset), `2E` (MCU reset), `61` (clear all data), and mode `99` on any
history read (including `60`, `62` and the temperature read `65`) or on `57` (deletes all alarms),
and mode `09` on history reads (workouts `5C` delete with it). `Frame.make` and the probe refuse them.

## Apple Health mapping

| Band data | HealthKit type |
|---|---|
| `52` per-minute steps / distance | `stepCount`, `distanceWalkingRunning` |
| `54`, `55` HR | `heartRate` |
| `56` HRV | `heartRateVariabilitySDNN` (band's HRV method unknown; SDNN is the only HealthKit type) |
| `66` SpO2 | `oxygenSaturation` |
| `53` sleep | `sleepAnalysis`: 2 Core, 3 Deep, 1 REM, 4/5 Awake |
| `5C` workouts | `HKWorkout` with steps, distance, average heart rate and active energy |

Not exported: the `56` blood-pressure estimate (not a measurement). Not read at all: `51` daily
totals (the `52` activity records hold the same steps and distance, and are kept longer).

## Open questions

1. Unknown fields in `51`, `52`, `56`, and the `16` events.
2. Triggering live SpO2 (`2A5F`) and cadence (`2A53`).

(Sleep stage values were settled by the cross-check below: 3 Deep, 1 REM, 2 Core, 4/5 Awake.)

## Reference SDK

The band matches the **JStyle "2025" SDK** opcode-for-opcode. Decompiled Android source (GPLv3):
`github.com/root1m3/plebble` → `core0/us/android/blesdk_2025/` (`DeviceConst.java` = opcodes,
`BleSDK.java` = command builders, `ResolveUtil.java` = parsers). Use it to confirm fields before guessing.

Useful extras from the SDK:
- `2A` set auto-monitoring: `2A enable(02/00) startH startM endH endM weekdayMask intervalLo intervalHi type` (BCD times; type 1=HR, 2=SpO2, 3=temp, 4=HRV). `2B` reads it.
- `03` device settings (units, 12/24h, bright screen, brightness, dial). `04` reads them.
- `16` from the band = "photo/music mode back" events (button presses), not data.
- `61` clears all band data. **Never send** (added to the danger list together with `12`, `2E`).
- No command exists to turn Bluetooth off or power the band down.

## Transfer behavior (measured 2026-10-02 with tools/pulse-sync)

- A page is exactly 50 notifications. Each notification carries whole records (225 B = 9 x 25,
  240 B = 10 x 24, 130 B = 1 sleep record); records never span packets.
- The last page ends with `<op> ff` appended to the final packet. Every final page had it.
- The band can pause about 3 s inside a page, and takes up to about 2.5 s to start one.
- After the reader stops early, the band finishes sending the page; those packets arrive after the
  next command and must be skipped (they start with the previous opcode).
- `16 xx yy` button events can arrive at any time, including right after an end marker.
- Right after a reconnect the band sometimes ignores the first command (set-time); a retry works.
- The band drops the connection when it moves out of range (walking around the house).
- Full first sync: about 10,000 records in 53 s. Repeat sync: about 15 s (one page per type).

## Sleep stage values (`53`), inferred 2026-10-02

No SDK documents the meaning: JStyle's own demo only prints `arraySleepQuality`, and the
react-native-ble-sdk-v8 wrapper's `0=awake 1=light 2=deep 3=REM` is a self-described guess for a
different device (values 0..3; this band sends 1..5). Inferred from about 100 nights
of this band's own data:

| Value | Share | Evidence | Meaning (confidence) |
|---|---|---|---|
| 5 | 8% | 37% of the first/last 30 min, 3% inside; runs median 26 min; HR +3.3 bpm vs night median | awake, falling asleep (high) |
| 4 | 1% | 1-3 min blips inside the night | brief awakening (high) |
| 2 | 49% | everywhere, textbook light-sleep share | light / core (high) |
| 3 | 21% | first sustained run 34 min after onset (median); longest run earlier (0.37 of night); steadiest HR (1.5 bpm/min) | deep (medium) |
| 1 | 21% | first sustained run 49 min after onset; share grows later in the night (16% -> 25%) | REM (medium) |
| 9, 10, 30 | <0.1% | single values, often the first minute of a chunk | marker/glitch, ignore |

Direct 1<->3 transitions are rare (77 and 24 vs about 1,300-1,700 via 2), as expected for REM<->deep.
Continuous HR overlaps only 1,558 night minutes, so HR evidence is thin.

### Cross-check against another tracker (2026-10-02)

Two nights were also recorded by another device in Apple Health.
- The band's clock ran on UTC then (2 h behind local), confirmed by onset/wake times matching after +2 h.
- 4/5 (awake), 2 (core), sleep onset and wake times agree.
- Both devices show the same alternating ~30-45 min blocks (one "1" and one "3" block per cycle), but
  which block is deep vs REM agrees only about 50/50, and the alignment score flips with a +/-15 min
  shift. The band's 1/3 behave like cycle-half labels. Chosen mapping: 3 = Deep, 1 = REM (first
  block after onset is deep on both devices; about 20% each, close to the other device's averages).

## Live data (measured 2026-10-02, band on wrist)

- `09 01 00` starts real-time activity: one 30-byte `09` packet per second until `09 00`.
  Layout (SDK `getActivityData`): steps u32 @1, calories x100 u32 @5 (about 1,350 kcal: seems to
  include resting burn), distance x10 m u32 @9, active time u32 @13, exercise time u32 @17,
  b27 = HR (matches 2A37), b28 unknown.
- `28 <type> 01` starts an on-demand measurement; one progress packet per second, then `28 ff`.
  Packet: `28 type hr spo2 hrv stress sys dia`. Stop with `28 <type> 00`.
  - type 2 (HR): about 30 s, live HR in b2. Not saved to history.
  - type 1 (HRV): about 75 s, final packet carries HR, HRV, stress, sys/dia. Saved to history (`56`).
    It is repeated a few times and **no `28 ff` follows** (verified on the phone 2026-10-02): treat the
    first packet with HRV > 0 as the result.
  - type 3 (SpO2): about 30 s, b3 stays 0 on this firmware (other bytes repeat the last HRV
    result). Not saved. Not usable.
- `2A5F` (PLX) and `2A53` (RSC) never sent data, passively or during measurements.
- Automatic tracking while worn: spot HR about every 3 min, SpO2 about every 10-60 min, HRV every
  10 min mainly at night, sleep and steps continuously. All of it lands in history and syncs.

## Storage on the band (observed 2026-10-02, full read)

Not documented by the SDK. Each history type keeps its own fixed-size store; the oldest record of
each type is from a different date, which points to per-type ring buffers that overwrite the oldest
records when full. Records exist only for time the band was worn.

| Type | Records held | Bytes | Typical rate when worn | Covers about |
|---|---|---|---|---|
| Daily totals | 31 | 0.8 KB | 1 per day | 31 days |
| Activity (10 min) | ~1,920 | 47 KB | ~18 per day | ~3.5 months |
| Sleep (2 h chunks) | ~513 | 65 KB | ~5 per night | ~100 nights |
| Continuous HR (15 min) | ~1,460 | 34 KB | ~8 per day | ~6 months |
| Spot HR | ~1,790 | 18 KB | ~30 per day (more on some days) | ~2 months or less |
| HRV | ~610 | 9 KB | ~9 per day | ~2 months |
| SpO2 | ~3,580 | 35 KB | ~40 per day | ~3 months |
| Temperature (`65`) | ~2,560 | 28 KB | 144 per day (every 10 min) | ~18 days of wear |

About 240 KB in total (temperature counted 2026-10-05). The app never deletes anything on the band (`99` and `61` are never sent),
so the band recycles its own oldest records; the phone keeps every record it has synced.

## Workouts (`5C`), read 2026-10-03

`5C 00` reads the workout history (same paging as the other history types, 50 per page, end marker
`5c ff`; mode `99`/`09` deletes, never sent). 25 bytes per workout (SDK `getExerciseData`):

| Offset | Field |
|---|---|
| 1-2 | index (LE) |
| 3-8 | start date/time, BCD |
| 9 | activity mode (all 63 stored workouts on this band: 9) |
| 10 | average heart rate |
| 11-12 | duration, seconds (LE) |
| 13-14 | steps (LE) |
| 15-16 | pace, min and s per km |
| 17-20 | calories, Float32 LE |
| 21-24 | distance in km, Float32 LE |

The band held about 60 workouts, all mode 9, 2-10 minutes long, at a
walking pace (11-15 min/km, HR 99-130): mode 9 looks like walks the band detects by itself.
Related commands: `19 <workMode> <activityMode>` starts or stops a workout from the phone; during
one the band sends `18` packets (see below). The app doesn't use them: its activities take heart
rate from the standard `2A37` stream.

## Vibration (verified 2026-10-03)

- `36 <n>` vibrates the band n times; ack `36 00`. `36 05` was clearly felt on the wrist; `36 02`
  was not noticed, so use 3 or more for alerts.
- `4D <type> <len> <utf8 text>` (variable length, no checksum) is the SDK's notification command
  (type 1 = SMS). Sent `4d 01 02 48 69` ("Hi"): no ack.

## Profile and phone-started workouts (verified 2026-10-03)

- `42` reads the profile: `42 sex age height weight stepLength ...` (sex 1 = male). Values are
  whole numbers (cm, kg, years); step length in cm. `02 sex age height weight stepLength` sets it
  (SDK `SetPersonalInfo`); the band uses it for its own stride, distance and calories.
- `19 <status> <mode>` controls a workout: status 1 start, 2 pause, 3 continue, 4 finish; mode
  0 run, 1 cycling, ... 9 climb (SDK naming; this band's auto-detected walks also use 9), 10 workout.
  Start ack: `19 01 <BCD date/time>`. Finish ack: `19 01`, then `18 ff`.
- While running, the band sends an `18` packet every second: b1 = heart rate (0 for about the
  first 15 s), b8-9 changing (probably part of a float, e.g. calories), b10 = elapsed seconds
  (LE). Steps stayed 0 while sitting still.
- A 41 s workout started from the phone was not added to the workout history (`5C`).

## More commands probed (2026-10-05)

- **Alarms:** `57 00` reads them (`57 ff` = none). `23` sets the whole list (SDK `setClockData`: 39-byte
  records `23 count n enable type hh mm weekmask len text(30)` + `23 ff`); a first write was not stored
  (read back `57 ff`). Not used yet. `57 99` deletes all alarms: never sent.
- **3-axis accelerometer:** `49 01` / `49 00` (SDK `RealTimeThreeAxisSensorData`): no answer on this
  firmware. Raw wrist movement is not available; sleep stages are the band's only movement-derived data.
- **Raw PPG:** `39` (SDK `GetPpgRawDataWithStatus`): not tried (optical data, not movement).
- `16 08 00` / `16 09 01` notifications arrive while moving the wrist (button / gesture events).
- Night measurement density (measured): about 50 SpO2, 40 HRV and 100-125 spot heart rate readings
  between 22:00 and 07:00.
