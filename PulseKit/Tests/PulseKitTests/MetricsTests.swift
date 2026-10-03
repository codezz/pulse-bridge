import Foundation
import Testing
@testable import PulseKit

struct ReadingsTests {
    let t0 = utcDate(2026, 10, 2, 10, 0)

    @Test func collectsEachKindSortedByTime() {
        let r = Readings(records: [
            makeRecord(.spotHR, t0 + 600, [70]),
            makeRecord(.spotHR, t0, [65]),
            makeRecord(.hrv, t0, [32, 0, 87, 57, 120, 75]),
            makeRecord(.spo2, t0, [98]),
        ])
        #expect(r.heartRate == [Reading(date: t0, value: 65), Reading(date: t0 + 600, value: 70)])
        #expect(r.hrv == [Reading(date: t0, value: 32)])
        #expect(r.spo2 == [Reading(date: t0, value: 98)])
    }

    @Test func continuousHeartRateSkipsZeroMinutes() {
        let r = Readings(records: [makeRecord(.continuousHR, t0, [80, 0, 90])])
        #expect(r.heartRate == [Reading(date: t0, value: 80), Reading(date: t0 + 120, value: 90)])
    }

    @Test func zeroSpotValuesAreSkipped() {
        let r = Readings(records: [makeRecord(.spotHR, t0, [0]), makeRecord(.spo2, t0, [0]), makeRecord(.hrv, t0, [0])])
        #expect(r.heartRate.isEmpty && r.spo2.isEmpty && r.hrv.isEmpty)
    }

    @Test func asleepMinutesExcludeAwakeStages() {
        // count 4, then minutes: 5 awake, 2 core, 3 deep, 4 awake
        let r = Readings(records: [makeRecord(.sleep, t0, [4, 5, 2, 3, 4])])
        #expect(!r.isAsleep(at: t0))
        #expect(r.isAsleep(at: t0 + 60))
        #expect(r.isAsleep(at: t0 + 150)) // inside the third minute
        #expect(!r.isAsleep(at: t0 + 180))
    }
}

@MainActor
struct RecordStoreRangeTests {
    @Test func returnsKindsInRangeOldestFirst() throws {
        let store = RecordStore(container: try RecordStore.container(inMemory: true))
        let t0 = utcDate(2026, 10, 2, 10, 0)
        try store.insert([
            makeRecord(.spotHR, t0 + 120, [70]),
            makeRecord(.spotHR, t0, [65]),
            makeRecord(.spo2, t0, [98]),
            makeRecord(.spotHR, t0 + 3600, [60]), // at `to`: excluded
        ], serial: "S")
        let found = try store.records(of: [.spotHR], from: t0, to: t0 + 3600)
        #expect(found.map(\.start) == [t0, t0 + 120])
    }
}

struct DailyMetricsTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }
    let day = utcDate(2026, 10, 2)

    private func metrics(_ records: [HistoryRecord]) -> DailyMetrics {
        DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
    }

    /// Spot HR readings every 3 min starting at `start`.
    private func spots(from start: Date, _ values: [UInt8]) -> [HistoryRecord] {
        values.enumerated().map { makeRecord(.spotHR, start + Double($0.offset * 180), [$0.element]) }
    }

    private func sleep(from start: Date, minutes: Int) -> HistoryRecord {
        makeRecord(.sleep, start, [UInt8(minutes)] + [UInt8](repeating: 2, count: minutes))
    }

    @Test func restingUsesTheLowestTenPercentDuringSleep() {
        let night = (0..<40).map { UInt8(50 + $0) }               // 00:00..01:57 asleep: 50...89
        let records = [sleep(from: day, minutes: 120)] + spots(from: day, night)
            + [makeRecord(.spotHR, day + 15 * 3600, [40])]        // awake afternoon: ignored
        #expect(metrics(records).restingHeartRate(on: day) == 52)  // lowest 4 of 40: 50 51 52 53
    }

    @Test func restingFallsBackToTheDayWithoutSleep() {
        let records = spots(from: day + 9 * 3600, [70, 72, 74, 60, 62, 64])
        #expect(metrics(records).restingHeartRate(on: day) == 62)  // lowest 3: 60 62 64
    }

    @Test func restingNeedsThreeReadings() {
        #expect(metrics(spots(from: day + 9 * 3600, [60, 61])).restingHeartRate(on: day) == nil)
    }

    @Test func nightWindowEdges() {
        let evening = day - 7 * 3600                               // D-1 17:00
        let records = [sleep(from: evening, minutes: 120), sleep(from: day + 11 * 3600, minutes: 120)] + [
            makeRecord(.spotHR, day - 6 * 3600 - 60, [30]),        // D-1 17:59: before the night
            makeRecord(.spotHR, day - 6 * 3600, [50]),             // D-1 18:00
            makeRecord(.spotHR, day - 6 * 3600 + 1800, [51]),
            makeRecord(.spotHR, day - 6 * 3600 + 3540, [52]),      // D-1 18:59
            makeRecord(.spotHR, day + 12 * 3600, [20]),            // D 12:00: after the night
        ]
        #expect(metrics(records).restingHeartRate(on: day) == 51)
    }

    @Test func hrvAveragesTheNightThenFallsBackToTheDay() {
        let night = [sleep(from: day, minutes: 120),
                     makeRecord(.hrv, day + 600, [30, 0, 60, 20, 110, 70]),
                     makeRecord(.hrv, day + 1200, [40, 0, 60, 20, 110, 70]),
                     makeRecord(.hrv, day + 14 * 3600, [90, 0, 80, 40, 120, 80])]
        #expect(metrics(night).hrv(on: day) == 35)
        let daytimeOnly = [makeRecord(.hrv, day + 14 * 3600, [90, 0, 80, 40, 120, 80])]
        #expect(metrics(daytimeOnly).hrv(on: day) == 90)
    }

    @Test func hrvReadingsFollowTheNightNotTheCalendarDay() {
        // Review finding: the D view plotted calendar-day HRV under the night's average.
        let records = [makeRecord(.hrv, day - 3 * 3600, [40, 0, 60, 20, 110, 70]),  // D-1 21:00: night of D
                       makeRecord(.hrv, day + 3600, [30, 0, 60, 20, 110, 70]),      // D 01:00: night of D
                       makeRecord(.hrv, day + 20 * 3600, [90, 0, 80, 40, 120, 80])] // D 20:00: night of D+1
        #expect(metrics(records).readings(.hrv, on: day).map(\.value) == [40, 30])
    }

    @Test func heartRateRangeIncludesContinuousMinutes() {
        let records = [makeRecord(.continuousHR, day + 10 * 3600, [80, 0, 90]), makeRecord(.spotHR, day + 11 * 3600, [70])]
        #expect(metrics(records).value(.heartRate, on: day) == DayRange(min: 70, average: 80, max: 90))
        #expect(metrics(records).readings(.heartRate, on: day).count == 3)
    }

    @Test func spo2Range() {
        let records = [makeRecord(.spo2, day + 3600, [96]), makeRecord(.spo2, day + 7200, [98])]
        #expect(metrics(records).value(.spo2, on: day) == DayRange(min: 96, average: 97, max: 98))
    }

    @Test func seriesSkipsDaysWithoutData() {
        let days = DailyMetrics.days(count: 3, endingOn: day + 3600, calendar: calendar)
        #expect(days == [day - 2 * 86400, day - 86400, day])
        let m = DailyMetrics(readings: Readings(records: [makeRecord(.spo2, day - 86400 + 60, [97])]), days: days, calendar: calendar)
        #expect(m.series(.spo2) == [DailyValue(day: day - 86400, range: DayRange(min: 97, average: 97, max: 97))])
    }
}
