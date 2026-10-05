import Foundation
import Testing
@testable import PulseKit

struct ReadinessTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }
    let today = utcDate(2026, 10, 5)

    private func day(_ offset: Int) -> Date { today + Double(offset) * 86400 }

    /// `values[0]` is today (last night), then the nights before.
    private func series(_ values: [Double?]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for (back, value) in values.enumerated() { if let value { result[day(-back)] = value } }
        return result
    }

    private func score(_ result: ReadinessResult) -> ReadinessScore? {
        if case .score(let s) = result { return s }
        return nil
    }

    @Test func atBaselineEverythingIsFull() throws {
        let r = Readiness.compute([.hrv: series([45] + Array(repeating: 42, count: 6)),
                                   .restingHeartRate: series([58] + Array(repeating: 60, count: 6))],
                                  sleepScore: 100, today: today, calendar: calendar)
        let s = try #require(score(r))
        #expect(s.value == 100)
        #expect(s.label == "Optimal")
        #expect(s.reason == "You're recovered")
        #expect(s.contributors.map(\.kind) == [.hrv, .restingHeartRate, .sleep])   // no activity data: left out
    }

    @Test func contributorsScaleLinearly() throws {
        // HRV at 90% of baseline: halfway between 75% (0) and 105% (100) = 50
        // Resting HR +3.5 over baseline: halfway between -1 (100) and +8 (0) = 50
        let r = Readiness.compute([.hrv: series([36] + Array(repeating: 40, count: 6)),
                                   .restingHeartRate: series([63.5] + Array(repeating: 60, count: 6))],
                                  sleepScore: 80, today: today, calendar: calendar)
        let s = try #require(score(r))
        let byKind = Dictionary(uniqueKeysWithValues: s.contributors.map { ($0.kind, $0.score) })
        #expect(byKind[.hrv] == 50)
        #expect(byKind[.restingHeartRate] == 50)
        // weights 35/25/20 rescaled over 80: (50*35 + 50*25 + 80*20) / 80 = 57.5
        #expect(s.value == 58)
        #expect(s.reason == "HRV 10% below your usual")
    }

    @Test func activityBalanceCountsYesterday() throws {
        // yesterday 25,000 steps vs 10,000 usual (250%): 40
        let steps = series([3_000, 25_000] + Array(repeating: 10_000, count: 14))
        let r = Readiness.compute([.hrv: series([42] + Array(repeating: 42, count: 6)), .steps: steps],
                                  sleepScore: nil, today: today, calendar: calendar)
        let s = try #require(score(r))
        #expect(s.contributors.first { $0.kind == .activity }?.score == 40)
        #expect(s.reason == "Big activity day yesterday")
    }

    @Test func calibratingWithoutBaseline() {
        let r = Readiness.compute([.hrv: series([42, 40, 41]), .restingHeartRate: series([60, 61])],
                                  sleepScore: 90, today: today, calendar: calendar)
        #expect(r == .calibrating(nightsNeeded: 3))
    }

    @Test func noReadingLastNightIsCalibratingToo() {
        let r = Readiness.compute([.hrv: series([nil] + Array(repeating: 42, count: 8))],
                                  sleepScore: 90, today: today, calendar: calendar)
        #expect(r == .calibrating(nightsNeeded: 0))
    }

    @Test func warmNightLowersReadiness() throws {
        // +0.6 °C: halfway between +0.2 (100) and +1.0 (0)
        let r = Readiness.compute([.hrv: series([42] + Array(repeating: 40, count: 6)),
                                   .temperature: series([37.0] + Array(repeating: 36.4, count: 6))],
                                  sleepScore: 90, today: today, calendar: calendar)
        let s = try #require(score(r))
        #expect(s.contributors.first { $0.kind == .temperature }?.score == 50)
        #expect(s.reason == "Temperature \(0.6.formatted(.number.precision(.fractionLength(1)))) °C above your usual")
    }

    /// A zero baseline (no real HRV values) can't produce a ratio: HRV is left out.
    @Test func zeroBaselineIsLeftOut() {
        let r = Readiness.compute([.hrv: series([42] + Array(repeating: 0, count: 6))], sleepScore: 90, today: today, calendar: calendar)
        #expect(r == .calibrating(nightsNeeded: 0))
    }

    @Test func restingHeartRateReason() throws {
        let r = Readiness.compute([.restingHeartRate: series([65] + Array(repeating: 60, count: 6))],
                                  sleepScore: 90, today: today, calendar: calendar)
        let s = try #require(score(r))
        #expect(s.reason == "Resting heart rate 5 above your usual")
    }
}
