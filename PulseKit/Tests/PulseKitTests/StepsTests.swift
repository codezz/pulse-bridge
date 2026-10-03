import Foundation
import Testing
@testable import PulseKit

struct StepsTests {
    let day = utcDate(2026, 10, 2)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    /// 10-minute activity block: total steps, distance in 10 m units, then 10 per-minute counts.
    private func block(_ start: Date, distance: UInt8, _ minutes: [UInt8]) -> HistoryRecord {
        let total = minutes.reduce(0) { $0 + Int($1) }
        return makeRecord(.activity, start, [UInt8(total & 0xFF), UInt8(total >> 8), 0, 0, distance, 0] + minutes)
    }

    private func metrics(_ records: [HistoryRecord], days: [Date]? = nil) -> DailyMetrics {
        DailyMetrics(readings: Readings(records: records), days: days ?? [day], calendar: calendar)
    }

    @Test func readingsCollectMinuteStepsAndBlockDistance() {
        let t0 = day + 10 * 3600
        let r = Readings(records: [block(t0, distance: 8, [68, 0, 0, 0, 47, 15, 0, 0, 0, 0])])
        #expect(r.steps == [Reading(date: t0, value: 68), Reading(date: t0 + 240, value: 47), Reading(date: t0 + 300, value: 15)])
        #expect(r.distance == [Reading(date: t0, value: 80)])
    }

    @Test func dailyTotalsAndHours() {
        let m = metrics([block(day + 10 * 3600, distance: 5, [50, 50] + Array(repeating: 0, count: 8)),
                         block(day + 10 * 3600 + 1800, distance: 2, [20] + Array(repeating: 0, count: 9)),
                         block(day + 14 * 3600, distance: 1, [7] + Array(repeating: 0, count: 9))])
        #expect(m.stepsTotal(on: day) == 127)
        #expect(m.distanceMeters(on: day) == 80)
        #expect(m.stepsByHour(on: day) == [Reading(date: day + 10 * 3600, value: 120), Reading(date: day + 14 * 3600, value: 7)])
        #expect(m.value(.steps, on: day) == DayRange(min: 127, average: 127, max: 127))
        #expect(m.readings(.steps, on: day) == m.stepsByHour(on: day))
    }

    @Test func daysWithoutStepsHaveNoValue() {
        let days = DailyMetrics.days(count: 2, endingOn: day, calendar: calendar)
        let m = metrics([block(day + 3600, distance: 1, [30] + Array(repeating: 0, count: 9))], days: days)
        #expect(m.value(.steps, on: day - 86400) == nil)
        #expect(m.series(.steps).map(\.day) == [day])
    }
}
