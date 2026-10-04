import Foundation
import Testing
@testable import PulseKit

struct InsightsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }
    let today = utcDate(2026, 10, 4)

    private func day(_ offset: Int) -> Date { today + Double(offset) * 86400 }

    /// `values[0]` is today, then yesterday, ...
    private func series(_ values: [Double?]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for (back, value) in values.enumerated() { if let value { result[day(-back)] = value } }
        return result
    }

    private func make(_ topic: InsightTopic, _ values: [Double?]) -> [Insight] {
        Insights.make([topic: series(values)], today: today, calendar: calendar)
    }

    @Test func restingHeartRateBelowAverageIsBetter() {
        let insights = make(.restingHeartRate, [56, 59, 59, 60, 58, 59])
        #expect(insights == [Insight(topic: .restingHeartRate, text: "Resting heart rate 56 bpm, 3 below your recent average", direction: .better)])
    }

    @Test func smallOrShortChangesSayNothing() {
        #expect(make(.restingHeartRate, [58, 59, 59, 60, 58, 59]).isEmpty)       // 1 bpm
        #expect(make(.restingHeartRate, [50, 59, 59, 60]).isEmpty)               // only 3 earlier nights
        #expect(make(.hrv, [43, 40, 41, 40, 39, 40]).isEmpty)                    // under 10%
    }

    @Test func hrvHigherIsBetter() {
        let insights = make(.hrv, [48, 40, 40, 40, 40, 40])
        #expect(insights.first?.direction == .better)
        #expect(insights.first?.text == "HRV 48 ms, 20% higher than usual")
    }

    @Test func sleepWeekOverWeek() {
        // last 7 nights 7h30, the 7 before 7h00
        let insights = make(.sleep, Array(repeating: 450, count: 7) + Array(repeating: 420, count: 7))
        #expect(insights == [Insight(topic: .sleep, text: "You slept 30 min more per night than the week before", direction: .better)])
    }

    @Test func stepsUseCompleteDays() {
        // today (partial) is ignored: yesterday back 7 days at 11,000 vs 10,000 before
        let values: [Double?] = [500] + Array(repeating: 11_000, count: 7) + Array(repeating: 10_000, count: 7)
        let insights = make(.steps, values)
        #expect(insights == [Insight(topic: .steps, text: "Steps up 10% on the week before", direction: .better)])
    }

    @Test func weekComparisonNeedsFourDaysEach() {
        let full = series(Array(repeating: 60, count: 7) + Array(repeating: 62, count: 7))
        #expect(Insights.week(full, today: today, calendar: calendar) == WeekComparison(this: 60, last: 62))
        let short = series([60, 60, 60, nil, nil, nil, nil] + Array(repeating: 62, count: 7))
        #expect(Insights.week(short, today: today, calendar: calendar) == nil)
    }
}
