import Foundation
import Testing
@testable import PulseKit

struct HeartRateSeriesTests {
    let t0 = utcDate(2026, 10, 2, 19, 0)

    @Test func keepsTheLastTenMinutes() {
        var s = HeartRateSeries()
        s.append(60, at: t0)
        s.append(61, at: t0 + 300)
        s.append(62, at: t0 + 601)
        #expect(s.samples.map(\.bpm) == [61, 62])
        #expect(s.latest == 62)
    }

    @Test func sessionStatsCoverTheWholeSession() {
        var s = HeartRateSeries()
        s.append(90, at: t0)
        s.append(60, at: t0 + 700) // the 90 is out of the chart window, still in the session
        s.append(63, at: t0 + 701)
        #expect(s.minimum == 60)
        #expect(s.maximum == 90)
        #expect(s.average == 71)
    }

    @Test func ignoresZero() {
        var s = HeartRateSeries()
        s.append(0, at: t0)
        #expect(s.samples.isEmpty)
        #expect(s.average == nil)
    }

    @Test func notStaleRightAfterAGap() {
        // Review finding: same bpm before backgrounding and after reopening 30 min later
        // used to count as "unchanged for 30 min".
        var s = HeartRateSeries()
        s.append(62, at: t0)
        s.append(62, at: t0 + 1800)
        #expect(!s.isStale(now: t0 + 1800))
        #expect(s.isStale(now: t0 + 1800 + 121))
    }

    @Test func gapStartsANewChartSegment() {
        var s = HeartRateSeries()
        s.append(60, at: t0)
        s.append(61, at: t0 + 1)
        s.append(70, at: t0 + 60) // disconnected for a minute
        #expect(s.samples.map(\.segment) == [0, 0, 1])
    }

    @Test func staleWhenUnchangedForTwoMinutes() {
        var s = HeartRateSeries()
        for second in stride(from: 0, through: 130, by: 1) { s.append(62, at: t0 + Double(second)) }
        #expect(!s.isStale(now: t0 + 119))
        #expect(s.isStale(now: t0 + 130))
        s.append(64, at: t0 + 131)
        #expect(!s.isStale(now: t0 + 131))
    }
}
