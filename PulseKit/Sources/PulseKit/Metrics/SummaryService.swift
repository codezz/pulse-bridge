import Foundation

/// Loads stored records for a range of days. Keeps no state: every load reads the store.
@MainActor
public struct SummaryService {
    static let kinds: [HistoryKind] = [.spotHR, .continuousHR, .hrv, .spo2, .sleep, .activity, .workout, .temperature]
    /// Sleep chunks are up to 2 h long, so a chunk starting this much before the first night still counts.
    static let lookBack: TimeInterval = 3 * 3600

    public let store: RecordStore
    private let calendar: Calendar

    public init(store: RecordStore, calendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        self.calendar = calendar
    }

    /// Metrics for the `days` days ending on the day of `last`.
    public func load(days count: Int, endingOn last: Date) throws -> DailyMetrics {
        let days = DailyMetrics.days(count: count, endingOn: last, calendar: calendar)
        let empty = DailyMetrics(readings: Readings(records: []), days: days, calendar: calendar)
        guard let first = days.first, let lastDay = days.last else { return empty }
        let from = empty.nightInterval(of: first).start.addingTimeInterval(-Self.lookBack)
        let to = empty.dayInterval(of: lastDay).end
        // Only sleep needs the extra days (the regularity contributor uses previous nights).
        let sleepFrom = from.addingTimeInterval(-Double(DailyMetrics.regularityNights + 1) * 86400)
        let records = try store.records(of: Self.kinds.filter { $0 != .sleep }, from: from, to: to)
            + store.records(of: [.sleep], from: sleepFrom, to: to)
        return DailyMetrics(readings: Readings(records: records), days: days, calendar: calendar)
    }
}
