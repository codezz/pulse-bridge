import Foundation
import Observation
import PulseKit

/// Data for the Today screen: the selected day's week plus enough history for sparklines and
/// insights. Reloaded on appear, after every sync and when another day is picked.
@MainActor
@Observable
final class SummaryModel {
    /// Days loaded, ending on the selected week's last day (or today): covers the day strip,
    /// 14-night sparklines and the two weeks insights compare.
    static let loadedDays = 35

    let service: SummaryService
    private(set) var metrics: DailyMetrics?
    private(set) var insights: [Insight] = []
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
            insights = metrics.map { Insights.make($0.insightSeries(), today: selectedDay, calendar: calendar) } ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
