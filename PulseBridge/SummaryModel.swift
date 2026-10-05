import Foundation
import Observation
import PulseKit

/// Data for the Today screen: the selected day's week plus enough history for sparklines and
/// insights. Reloaded on appear, after every sync and when another day is picked.
@MainActor
@Observable
final class SummaryModel {
    /// Days loaded, ending on the selected week's last day (or today): covers the day strip, the
    /// readiness chart's 14 days with their full 30-night baseline (and up to 6 days of the week
    /// after the selected day), sparklines and the two weeks insights compare.
    static let loadedDays = 50

    let service: SummaryService
    private(set) var metrics: DailyMetrics?
    private(set) var insights: [Insight] = []
    /// Per-day values of the loaded window (insights, readiness).
    private(set) var series: [InsightTopic: [Date: Double]] = [:]
    private(set) var readiness: ReadinessResult?
    private(set) var error: String?
    /// Start of the day shown on Today. Change it with `select(_:)`.
    private(set) var selectedDay = Calendar.current.startOfDay(for: .now)
    /// True while the user is on today: after midnight (or a night in the background) Today moves on
    /// to the new day instead of staying on yesterday.
    @ObservationIgnored private var followsToday = true
    /// Last day of the loaded window; another day in the same window only recomputes insights.
    @ObservationIgnored private var loadedEnd: Date?

    /// False until the first load finished, so cards show placeholders instead of "No data".
    var isLoaded: Bool { metrics != nil || error != nil }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    init(service: SummaryService) {
        self.service = service
    }

    func select(_ day: Date) {
        let calendar = Calendar.current
        selectedDay = min(calendar.startOfDay(for: day), calendar.startOfDay(for: .now))
        followsToday = calendar.isDateInToday(selectedDay)
        load(force: false)
    }

    /// Readiness on a day of the loaded window (the detail chart asks for the last 14).
    func readiness(on day: Date) -> ReadinessResult? {
        guard let metrics else { return nil }
        return Readiness.compute(series, sleepScore: metrics.sleepScore(on: day)?.value, today: day, calendar: .current)
    }

    /// Fresh data (after a sync, on returning to the app, at midnight).
    func reload() {
        let today = Calendar.current.startOfDay(for: .now)
        if followsToday || selectedDay > today { selectedDay = today }
        load(force: true)
    }

    private func load(force: Bool) {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: DayStrip.weekStart(of: selectedDay))!
        let end = min(weekEnd, calendar.startOfDay(for: .now))
        do {
            if force || loadedEnd != end || metrics == nil {
                metrics = try service.load(days: Self.loadedDays, endingOn: end)
                loadedEnd = end
            }
            series = metrics?.insightSeries() ?? [:]
            insights = Insights.make(series, today: selectedDay, calendar: calendar)
            readiness = readiness(on: selectedDay)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
