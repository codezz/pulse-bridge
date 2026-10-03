import Foundation
import Testing
@testable import PulseKit

/// Per-minute stages from `start`, one entry per value.
func stages(from start: Date, _ values: [SleepStage]) -> [Date: SleepStage] {
    Dictionary(uniqueKeysWithValues: values.enumerated().map { (start + Double($0.offset * 60), $0.element) })
}

func repeated(_ stage: SleepStage, _ count: Int) -> [SleepStage] { Array(repeating: stage, count: count) }

struct SleepAnalysisTests {
    let day = utcDate(2026, 10, 2)
    var window: DateInterval { DateInterval(start: day - 6 * 3600, end: day + 12 * 3600) }

    @Test func readingsKeepTheStageOfEachMinute() {
        let t0 = day + 3600
        let r = Readings(records: [makeRecord(.sleep, t0, [3, 5, 2, 3])])
        #expect(r.sleepStages == [t0: .awake, t0 + 60: .core, t0 + 120: .deep])
        #expect(!r.isAsleep(at: t0) && r.isAsleep(at: t0 + 90))
    }

    @Test func overlappingRecordsPreferTheAsleepStage() {
        let t0 = day + 3600
        for order in [[0, 1], [1, 0]] {
            let records = [makeRecord(.sleep, t0, [1, 2]), makeRecord(.sleep, t0, [1, 4])]
            let r = Readings(records: order.map { records[$0] })
            #expect(r.sleepStages[t0] == .core)
        }
    }

    @Test func precomputedSessionsGiveTheSameNight() {
        let all = stages(from: day - 3600, repeated(.core, 300)).merging(stages(from: day + 10 * 3600, repeated(.core, 30))) { a, _ in a }
        #expect(SleepAnalysis.night(in: window, sessions: SleepAnalysis.sessions(all)) == SleepAnalysis.night(in: window, stages: all))
    }

    @Test func gapsUpToAnHourAreMerged() {
        let first = stages(from: day, repeated(.core, 10))                       // last minute starts at +9 min
        let merged = first.merging(stages(from: day + 600 + 59 * 60, repeated(.core, 10))) { a, _ in a }
        let split = first.merging(stages(from: day + 600 + 61 * 60, repeated(.core, 10))) { a, _ in a }
        #expect(SleepAnalysis.sessions(merged).count == 1)
        #expect(SleepAnalysis.sessions(split).count == 2)
    }

    @Test func nightPicksTheSessionWithMostSleep() {
        let main = stages(from: day - 3600, repeated(.core, 360))                 // 23:00 to 05:00
        let nap = stages(from: day + 10 * 3600, repeated(.core, 30))             // 10:00 to 10:30
        let night = SleepAnalysis.night(in: window, stages: main.merging(nap) { a, _ in a })
        #expect(night?.asleep == 360)
    }

    @Test func sessionEndingAfterTheWindowIsIgnored() {
        let late = stages(from: day + 11 * 3600, repeated(.core, 90))            // ends 12:30
        #expect(SleepAnalysis.night(in: window, stages: late) == nil)
    }

    @Test func sessionWithoutSleepIsNoNight() {
        #expect(SleepAnalysis.night(in: window, stages: stages(from: day, repeated(.awake, 60))) == nil)
    }

    @Test func gapsInsideASessionCountAsAwake() throws {
        // Review finding: 21 Mar showed in bed 10h30 but the stages added up to less.
        let night = stages(from: day, repeated(.core, 60)).merging(stages(from: day + 70 * 60, repeated(.deep, 60))) { a, _ in a }
        let n = try #require(SleepAnalysis.night(in: window, stages: night))
        #expect(n.inBed == 130)
        #expect(n.minutes[.awake] == 10)
        #expect(n.minutes.values.reduce(0, +) == n.inBed)
        #expect(n.awakeAfterOnset == 10)
        #expect(n.awakenings == 1)
        #expect(n.segments.map(\.stage) == [.core, .awake, .deep])
    }

    @Test func longAwakeningsAreFiveMinutesOrMore() throws {
        let values = repeated(.core, 30) + repeated(.awake, 6) + repeated(.core, 30) + repeated(.awake, 4) + repeated(.core, 30)
        let n = try #require(SleepAnalysis.night(in: window, stages: stages(from: day, values)))
        #expect(n.awakenings == 2)
        #expect(n.longAwakenings == 1)
    }

    @Test func timingsAndCounts() throws {
        let start = day - 3600                                                   // 23:00
        let values = repeated(.awake, 20) + repeated(.core, 60) + repeated(.awake, 3) + repeated(.core, 30)
            + repeated(.awake, 1) + repeated(.deep, 30) + repeated(.rem, 10) + repeated(.awake, 5)
        let n = try #require(SleepAnalysis.night(in: window, stages: stages(from: start, values)))
        #expect(n.inBedStart == start)
        #expect(n.inBed == 159)
        #expect(n.fellAsleep == start + 20 * 60)
        #expect(n.latency == 20)
        #expect(n.wokeUp == start + 154 * 60)
        #expect(n.asleep == 130)
        #expect(n.minutes[.deep] == 30 && n.minutes[.rem] == 10 && n.minutes[.core] == 90)
        #expect(n.awakeAfterOnset == 4)
        #expect(n.awakenings == 1)                                               // the 1-minute blip doesn't count
        #expect(n.segments.count == 8)
        #expect(abs(n.efficiency - 130.0 / 159.0) < 0.0001)
    }
}

struct SleepScoreTests {
    let day = utcDate(2026, 10, 2)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    /// A night with the given properties; defaults are a perfect night (score 100 with steady history).
    private func night(hours: Double = 8, efficiency: Double = 0.95, awake: Int = 10, longAwakenings: Int = 0,
                       rem: Double = 0.25, deep: Double = 0.2, latency: Int = 12, midpoint: Date? = nil) -> SleepNight {
        let asleep = Int(hours * 60)
        let mid = midpoint ?? day + 2 * 3600
        let fell = mid - Double(asleep + awake) * 30
        let woke = fell + Double(asleep + awake) * 60
        let start = fell - Double(latency * 60)
        let remMin = Int(Double(asleep) * rem), deepMin = Int(Double(asleep) * deep)
        return SleepNight(inBedStart: start, inBedEnd: start + Double(asleep) / efficiency * 60,
                          fellAsleep: fell, wokeUp: woke,
                          minutes: [.rem: remMin, .deep: deepMin, .core: asleep - remMin - deepMin, .awake: awake],
                          awakeAfterOnset: awake, awakenings: longAwakenings, longAwakenings: longAwakenings, segments: [])
    }

    /// Five previous nights with the default midpoint (02:00).
    private var steady: [Date] { (1...5).map { day + 2 * 3600 - Double($0) * 86400 } }

    private func score(_ n: SleepNight, history: [Date]? = nil) -> SleepScore {
        SleepScore(night: n, calendar: calendar, recentMidpoints: history ?? steady)
    }

    private func value(_ n: SleepNight, _ c: SleepScore.Contributor, history: [Date]? = nil) -> Int? {
        score(n, history: history).contributors[c]
    }

    @Test func perfectNightScores100() {
        #expect(score(night()).value == 100)
        #expect(score(night()).label == "Optimal")
    }

    @Test func weights() {
        let w = Dictionary(uniqueKeysWithValues: SleepScore.Contributor.allCases.map { ($0, $0.weight) })
        #expect(w == [.totalSleep: 35, .efficiency: 15, .restfulness: 15, .regularity: 15, .latency: 10, .rem: 5, .deep: 5])
    }

    @Test func totalSleep() {
        #expect(value(night(hours: 4), .totalSleep) == 0)
        #expect(value(night(hours: 5.5), .totalSleep) == 50)
        #expect(value(night(hours: 7), .totalSleep) == 100)
        #expect(value(night(hours: 9.5), .totalSleep) == 100)
        #expect(value(night(hours: 11), .totalSleep) == 90)
    }

    @Test func efficiency() {
        #expect(value(night(efficiency: 0.7), .efficiency) == 0)
        #expect(value(night(efficiency: 0.8), .efficiency) == 50)
        #expect(value(night(efficiency: 0.9), .efficiency) == 100)
    }

    @Test func restfulnessAveragesAwakeTimeAndLongAwakenings() {
        #expect(value(night(awake: 20), .restfulness) == 100)
        #expect(value(night(awake: 40), .restfulness) == 75)                      // (50 + 100) / 2
        #expect(value(night(awake: 10, longAwakenings: 2), .restfulness) == 83)   // (100 + 66.7) / 2
        #expect(value(night(awake: 60, longAwakenings: 4), .restfulness) == 0)
    }

    @Test func regularityAgainstTheUsualMidpoint() {
        #expect(value(night(midpoint: day + 2 * 3600 + 1200), .regularity) == 100) // 20 min off
        #expect(value(night(midpoint: day + 3 * 3600 + 900), .regularity) == 50)   // 75 min off
        #expect(value(night(midpoint: day + 4 * 3600), .regularity) == 0)          // 2 h off
        #expect(score(night()).usualMidpoint == 120)
    }

    @Test func regularityAcrossMidnight() {
        let history = [day - 600 - 86400, day + 600 - 2 * 86400, day - 3 * 86400]  // 23:50, 00:10, 00:00
        #expect(value(night(midpoint: day + 1200), .regularity, history: history) == 100)
        #expect(score(night(), history: history).usualMidpoint == 0)
    }

    @Test func regularityFallsBackToTheClockWindowWithFewNights() {
        let two = Array(steady.prefix(2))
        #expect(value(night(midpoint: day + 5 * 3600), .regularity, history: two) == 50)  // 2 h after 03:00
        #expect(value(night(midpoint: day - 3600), .regularity, history: []) == 75)        // 23:00
        #expect(score(night(), history: two).usualMidpoint == nil)
    }

    @Test func fallbackWindowUsesTheClockOnDaylightSavingNights() {
        // 2026-03-29 in Bucharest: clocks jump 03:00 -> 04:00. A 04:30 midpoint is 90 min after the window.
        var bucharest = Calendar(identifier: .gregorian)
        bucharest.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        let midpoint = bucharest.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 4, minute: 30))!
        #expect(SleepScore(night: night(midpoint: midpoint), calendar: bucharest).contributors[.regularity] == 63)
    }

    @Test func latency() {
        #expect(value(night(latency: 3), .latency) == 85)
        #expect(value(night(latency: 5), .latency) == 100)
        #expect(value(night(latency: 30), .latency) == 100)
        #expect(value(night(latency: 45), .latency) == 50)
        #expect(value(night(latency: 60), .latency) == 0)
    }

    @Test func stages() {
        #expect(value(night(rem: 0.05), .rem) == 0)
        #expect(value(night(rem: 0.25), .rem) == 100)
        #expect(value(night(rem: 0.45), .rem) == 50)                               // over 40%
        #expect(value(night(deep: 0.03), .deep) == 0)
        #expect(value(night(deep: 0.1), .deep) == 54)                              // (10 - 3) / 13
        #expect(value(night(deep: 0.2), .deep) == 100)
    }

    @Test func weightedTotal() {
        // Only total sleep below full: 6.4 h -> 80; 100 - 35% of 20 = 93.
        #expect(score(night(hours: 6.4)).value == 93)
    }

    @Test func shortNightsScoreAtMost70() {
        #expect(score(night(hours: 5.5)).value == 70)
        #expect(score(night(hours: 6)).value > 70)
    }

    @Test func labels() {
        #expect(SleepScore.label(for: 85) == "Optimal")
        #expect(SleepScore.label(for: 84) == "Good")
        #expect(SleepScore.label(for: 70) == "Good")
        #expect(SleepScore.label(for: 69) == "Fair")
        #expect(SleepScore.label(for: 60) == "Fair")
        #expect(SleepScore.label(for: 59) == "Pay attention")
    }
}

struct DailySleepTests {
    let day = utcDate(2026, 10, 2)
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    private func chunk(_ start: Date, _ values: [UInt8]) -> HistoryRecord {
        makeRecord(.sleep, start, [UInt8(values.count)] + values)
    }

    @Test func sleepEndingAfterNoonStillCounts() {
        // Review finding: a 04:00-12:30 sleep belonged to no night.
        let late = chunk(day + 4 * 3600, Array(repeating: 2, count: 120)) // 04:00-06:00
        let records = [late, chunk(day + 6 * 3600, Array(repeating: 2, count: 120)), chunk(day + 8 * 3600, Array(repeating: 2, count: 120)),
                       chunk(day + 10 * 3600, Array(repeating: 2, count: 120)), chunk(day + 12 * 3600, Array(repeating: 2, count: 30))]
        let m = DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
        #expect(m.sleep(on: day)?.asleep == 510)
    }

    @Test func sleepOnDayComesFromTheRecords() throws {
        let records = [chunk(day - 3600, [5, 5] + Array(repeating: 2, count: 118)), chunk(day + 3600, Array(repeating: 3, count: 60))]
        let m = DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
        let night = try #require(m.sleep(on: day))
        #expect(night.asleep == 178)
        #expect(night.latency == 2)
        #expect(m.sleepSeries().map(\.day) == [day])
    }

    @Test func nightVitalsUseTheSession() {
        let records = [chunk(day, Array(repeating: 2, count: 60)),
                       makeRecord(.spotHR, day + 600, [58]), makeRecord(.spotHR, day + 1200, [52]),
                       makeRecord(.spotHR, day + 2 * 3600, [45])]               // after the session: ignored
        let m = DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
        #expect(m.lowestHeartRate(on: day) == Reading(date: day + 1200, value: 52))
        #expect(m.readings(.heartRate, during: m.sleep(on: day)!).map(\.value) == [58, 52])
    }

    @Test func lowestHeartRateComesFromTheMainSleep() {
        let records = [chunk(day - 6 * 3600 + 600, Array(repeating: 2, count: 30)),  // 18:10 nap
                       makeRecord(.spotHR, day - 6 * 3600 + 900, [44]),              // during the nap
                       chunk(day, Array(repeating: 2, count: 120)),                   // main sleep 00:00-02:00
                       makeRecord(.spotHR, day + 1800, [55])]
        let m = DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
        #expect(m.lowestHeartRate(on: day)?.value == 55)
    }

    @Test func sleepScoreUsesThePreviousNights() throws {
        // Three earlier nights 00:00-01:00 (midpoint 00:30), tonight 01:00-02:00 (midpoint 01:30): 60 min off.
        let earlier = (1...3).map { chunk(day - Double($0) * 86400, Array(repeating: 2, count: 60)) }
        let m = DailyMetrics(readings: Readings(records: earlier + [chunk(day + 3600, Array(repeating: 2, count: 60))]),
                             days: [day], calendar: calendar)
        let score = try #require(m.sleepScore(on: day))
        #expect(score.usualMidpoint == 30)
        #expect(score.contributors[.regularity] == 67)
        #expect(m.sleepSeries().first?.score == score)
    }

    @Test func seriesSkipsNightsWithoutSleep() {
        let days = DailyMetrics.days(count: 2, endingOn: day, calendar: calendar)
        let m = DailyMetrics(readings: Readings(records: [chunk(day, Array(repeating: 2, count: 60))]), days: days, calendar: calendar)
        #expect(m.sleepSeries().map(\.day) == [day])
    }
}
