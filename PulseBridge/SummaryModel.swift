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
    /// Start of the day shown on Today.
    var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet { if !Calendar.current.isDate(oldValue, inSameDayAs: selectedDay) { reload() } }
    }

    /// False until the first load finished, so cards show placeholders instead of "No data".
    var isLoaded: Bool { metrics != nil || error != nil }
    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    init(service: SummaryService) {
        self.service = service
    }

    func reload() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if selectedDay > today { selectedDay = today }
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: DayStrip.weekStart(of: selectedDay))!
        let end = min(weekEnd, today)
        do {
            let loaded = try service.load(days: Self.loadedDays, endingOn: end)
            metrics = loaded
            insights = Insights.make(loaded.insightSeries(), today: selectedDay, calendar: calendar)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
