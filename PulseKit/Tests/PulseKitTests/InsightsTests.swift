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

    @Test func warmerNightIsAHighlight() {
        let insights = make(.temperature, [36.9] + Array(repeating: 36.4, count: 6))
        #expect(insights == [Insight(topic: .temperature, text: "Night temperature 0.5 °C above your usual", direction: .worse)])
        #expect(make(.temperature, [36.6] + Array(repeating: 36.4, count: 6)).isEmpty)     // 0.2 °C
    }

    @Test func shortWeeksSayNothing() {
        // only 3 nights in the last week
        #expect(make(.sleep, [450, 450, 450, nil, nil, nil, nil] + Array(repeating: 420, count: 7)).isEmpty)
        // only 3 complete days in the last week (today is ignored)
        let steps: [Double?] = [500, 11_000, 11_000, 11_000, nil, nil, nil, nil] + Array(repeating: 10_000, count: 7)
        #expect(make(.steps, steps).isEmpty)
    }

    @Test func stepsWithAnEmptyEarlierWeekSayNothing() {
        let values: [Double?] = [500] + Array(repeating: 11_000, count: 7) + Array(repeating: 0, count: 7)
        #expect(make(.steps, values).isEmpty)
    }

    /// Trends arrows use the same thresholds as the highlights: small changes are neutral.
    @Test func trendDirectionUsesTopicThresholds() {
        #expect(Insights.direction(.steps, WeekComparison(this: 10_030, last: 10_000)) == .neutral)
        #expect(Insights.direction(.steps, WeekComparison(this: 11_500, last: 10_000)) == .better)
        #expect(Insights.direction(.restingHeartRate, WeekComparison(this: 61, last: 60)) == .neutral)
        #expect(Insights.direction(.restingHeartRate, WeekComparison(this: 57, last: 60)) == .better)
        #expect(Insights.direction(.sleep, WeekComparison(this: 410, last: 420)) == .neutral)
        #expect(Insights.direction(.sleep, WeekComparison(this: 395, last: 420)) == .worse)
        #expect(Insights.direction(.hrv, WeekComparison(this: 46, last: 40)) == .better)
        #expect(Insights.direction(.spo2, WeekComparison(this: 96.5, last: 97)) == .neutral)
    }

    @Test func weekComparisonNeedsFourDaysEach() {
        let full = series(Array(repeating: 60, count: 7) + Array(repeating: 62, count: 7))
        #expect(Insights.week(full, today: today, calendar: calendar) == WeekComparison(this: 60, last: 62))
        let short = series([60, 60, 60, nil, nil, nil, nil] + Array(repeating: 62, count: 7))
        #expect(Insights.week(short, today: today, calendar: calendar) == nil)
    }
}
