import Foundation
import Testing
@testable import PulseKit

@MainActor
struct SummaryServiceTests {
    let store: RecordStore
    let service: SummaryService
    let day = utcDate(2026, 10, 2)

    init() throws {
        store = RecordStore(container: try RecordStore.container(inMemory: true))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        service = SummaryService(store: store, calendar: calendar)
    }

    @Test func emptyStoreGivesNoValues() throws {
        let m = try service.load(days: 7, endingOn: day)
        #expect(m.days.count == 7)
        for metric in Metric.allCases { #expect(m.series(metric).isEmpty) }
    }

    @Test func loadsTheRangeAndTheNightBeforeIt() throws {
        try store.insert([
            makeRecord(.spo2, day - 86400 + 3600, [97]),     // previous day
            makeRecord(.spo2, day + 3600, [98]),             // today
            makeRecord(.spo2, day - 2 * 86400, [90]),        // outside a 2-day range
        ], serial: "S")
        let m = try service.load(days: 2, endingOn: day + 7200)
        #expect(m.series(.spo2).map(\.range.average) == [97, 98])
    }

    @Test func loadIncludesSleepChunksStartingBeforeTheWindow() throws {
        // Night of D starts at D-1 18:00; this 2 h chunk starts at 16:30 and covers 18:00-18:30.
        let chunk = makeRecord(.sleep, day - 7.5 * 3600, [120] + [UInt8](repeating: 2, count: 120))
        let readings = (0..<3).map { makeRecord(.spotHR, day - 6 * 3600 + Double($0 * 600), [UInt8(50 + $0)]) }
        try store.insert([chunk] + readings + [makeRecord(.spotHR, day + 10 * 3600, [40])], serial: "S")
        let m = try service.load(days: 1, endingOn: day)
        #expect(m.restingHeartRate(on: day) == 51) // asleep readings 50, 51, 52; daytime 40 ignored
    }

    @Test func loadIncludesTwoWeeksOfSleepHistory() throws {
        // Nights 8-10 days back and today, all 04:30-05:30 (midpoint 05:00). With that history today's
        // regularity is 100; the clock-window fallback would give 50.
        let nights = [0, 8, 9, 10].map { makeRecord(.sleep, day - Double($0) * 86400 + 4.5 * 3600, [60] + [UInt8](repeating: 2, count: 60)) }
        try store.insert(nights, serial: "S")
        let m = try service.load(days: 1, endingOn: day)
        #expect(m.sleepScore(on: day)?.contributors[.regularity] == 100)
    }
}
