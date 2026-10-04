import Foundation
import Testing
@testable import PulseKit

struct HeartRateChartRangeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    @Test func liveShowsTheLastHour() {
        let now = utcDate(2026, 10, 3, 14, 30)
        #expect(HeartRateChartRange.domain(live: true, now: now, calendar: calendar) == utcDate(2026, 10, 3, 13, 30)...now)
    }

    @Test func todayStartsAtMidnight() {
        let now = utcDate(2026, 10, 3, 14, 30)
        #expect(HeartRateChartRange.domain(live: false, now: now, calendar: calendar) == utcDate(2026, 10, 3)...now)
    }

    @Test func dayRangeIsAtLeastAnHour() {
        let now = utcDate(2026, 10, 3, 0, 10)
        #expect(HeartRateChartRange.domain(live: false, now: now, calendar: calendar) == utcDate(2026, 10, 3)...utcDate(2026, 10, 3, 1, 0))
    }

    @Test func liveCrossesMidnight() {
        let now = utcDate(2026, 10, 3, 0, 10)
        #expect(HeartRateChartRange.domain(live: true, now: now, calendar: calendar).lowerBound == utcDate(2026, 10, 2, 23, 10))
    }
}

struct RelativeTimeTests {
    let now = utcDate(2026, 10, 3, 14, 0)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    @Test func steps() {
        #expect(RelativeTime.text(now - 30, now: now) == "just now")
        #expect(RelativeTime.text(now - 60, now: now) == "1 min ago")
        #expect(RelativeTime.text(now - 59 * 60, now: now) == "59 min ago")
        #expect(RelativeTime.text(now - 3600, now: now) == "1 h ago")
        #expect(RelativeTime.text(now - 23 * 3600, now: now) == "23 h ago")
        #expect(RelativeTime.text(now - 86400, now: now, calendar: calendar) == "yesterday")
        #expect(RelativeTime.text(now - 3 * 86400, now: now, calendar: calendar) == "3 days ago")
    }

    @Test func daysAreCalendarDays() {
        let now = utcDate(2026, 10, 4, 0, 30)
        #expect(RelativeTime.text(utcDate(2026, 10, 2, 23, 30), now: now, calendar: calendar) == "2 days ago")   // 25 h, 2 calendar days
        #expect(RelativeTime.text(utcDate(2026, 10, 3, 0, 20), now: now, calendar: calendar) == "yesterday")      // 24 h 10 min
        #expect(RelativeTime.text(utcDate(2026, 10, 3, 1, 0), now: now, calendar: calendar) == "23 h ago")
    }

    @Test func futureDatesReadJustNow() {
        #expect(RelativeTime.text(now + 90, now: now) == "just now")
    }
}
