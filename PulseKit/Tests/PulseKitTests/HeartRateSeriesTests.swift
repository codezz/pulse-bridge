import Foundation
import Testing
@testable import PulseKit

struct HeartRateSeriesTests {
    let t0 = utcDate(2026, 10, 2, 19, 0)

    @Test func keepsTheLastHour() {
        var s = HeartRateSeries()
        s.append(60, at: t0)
        s.append(61, at: t0 + 1800)
        s.append(62, at: t0 + 3601)
        #expect(s.samples.map(\.bpm) == [61, 62])
        #expect(s.latest == 62)
    }

    @Test func keepsOneSampleEveryFiveSeconds() {
        var s = HeartRateSeries()
        for second in 0..<60 { s.append(60 + second, at: t0 + Double(second)) }
        // t0, t5, ..., t55 kept, plus the newest reading (t59) as the provisional last point.
        #expect(s.samples.count == 13)
        let kept = s.samples.dropLast().map { $0.date.timeIntervalSince(t0) }
        #expect(kept == stride(from: 0.0, through: 55, by: 5).map { $0 })
        #expect(s.latest == 119)
        #expect(s.maximum == 119)        // session stats still see every reading
        #expect(s.minimum == 60)
    }

    @Test func zoneRunsSplitAtZoneChangesAndStayConnected() {
        let zones = HeartRateZones(max: 180, resting: 60)   // Z1 from 120, Z2 from 132
        var s = HeartRateSeries()
        s.append(100, at: t0)
        s.append(101, at: t0 + 5)
        s.append(125, at: t0 + 10)
        s.append(126, at: t0 + 15)
        let runs = s.zoneRuns(zones)
        #expect(runs.map(\.zone) == [0, 1])
        #expect(runs[0].samples.map(\.bpm) == [100, 101, 125])   // carries the next point
        #expect(runs[1].samples.map(\.bpm) == [125, 126])
        #expect(runs.map(\.id) == [0, 1])
    }

    @Test func zoneRunsDontJoinAcrossAGap() {
        let zones = HeartRateZones(max: 180, resting: 60)
        var s = HeartRateSeries()
        s.append(100, at: t0)
        s.append(101, at: t0 + 5)
        s.append(140, at: t0 + 60)       // reconnected a minute later, now zone 2
        let runs = s.zoneRuns(zones)
        #expect(runs.map(\.zone) == [0, 2])
        #expect(runs[0].samples.map(\.bpm) == [100, 101])        // no bridge across the gap
    }

    @Test func zoneRunsSkipSamplesBeforeTheChartStart() {
        let zones = HeartRateZones(max: 180, resting: 60)
        var s = HeartRateSeries()
        s.append(100, at: t0)
        s.append(101, at: t0 + 5)
        s.append(102, at: t0 + 10)
        let runs = s.zoneRuns(zones, since: t0 + 5)
        #expect(runs.flatMap(\.samples).map(\.bpm) == [101, 102])
    }

    @Test func sessionStatsCoverTheWholeSession() {
        var s = HeartRateSeries()
        s.append(90, at: t0)
        s.append(60, at: t0 + 700) // the session keeps the 90 whatever the chart window holds
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
