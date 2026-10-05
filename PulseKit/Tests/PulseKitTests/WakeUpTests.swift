import Foundation
import Testing
@testable import PulseKit

struct WakeUpTests {
    let t0 = utcDate(2026, 10, 4, 23, 0)
    private func at(_ hour: Int, _ minute: Int) -> Date {
        t0 + Double(((hour + 24 - 23) % 24) * 3600 + minute * 60)
    }

    /// 23:00 core, 01:00 deep, 01:30 core, 02:00 REM, 02:30 core until 07:00.
    private var night: SleepNight {
        let parts: [(Int, Int, SleepStage)] = [(23, 0, .core), (1, 0, .deep), (1, 30, .core), (2, 0, .rem), (2, 30, .core)]
        let ends = parts.dropFirst().map { at($0.0, $0.1) } + [at(7, 0)]
        let segments = zip(parts, ends).map { SleepNight.Segment(start: at($0.0.0, $0.0.1), end: $0.1, stage: $0.0.2) }
        return SleepNight(inBedStart: t0, inBedEnd: at(7, 0), fellAsleep: t0, wokeUp: at(7, 0), minutes: [:],
                          awakeAfterOnset: 0, awakenings: 0, segments: segments)
    }

    private var heart: [Reading] {
        var readings = stride(from: 0.0, to: 8 * 3600, by: 300).map { Reading(date: t0 + $0 + 60, value: 60) }
        let spikes: [(Date, Double)] = [(at(23, 6), 80),    // first 15 min: falling asleep
                                        (at(1, 31), 75),    // just out of deep sleep
                                        (at(1, 36), 76),    // same wake-up
                                        (at(2, 9), 75),     // in REM: a dream
                                        (at(2, 14), 90),    // in REM but +30: too high for a dream
                                        (at(2, 33), 74),    // coming out of REM
                                        (at(5, 0), 75)]     // no stage change: unclear
        readings += spikes.map { Reading(date: $0.0, value: $0.1) }
        return readings.sorted { $0.date < $1.date }
    }

    @Test func countsRisesTheBandsStagesExplain() {
        let wakeUps = SleepAnalysis.estimatedWakeUps(night, heartRate: heart)
        #expect(wakeUps.map(\.date) == [at(1, 31), at(2, 14), at(2, 33)])
        #expect(wakeUps.map(\.reason) == [.outOfDeepSleep, .highHeartRate, .outOfREM])
        #expect(wakeUps.first?.bpm == 75)
    }

    @Test func tooFewReadingsSayNothing() {
        #expect(SleepAnalysis.estimatedWakeUps(night, heartRate: Array(heart.prefix(5))).isEmpty)
    }
}
