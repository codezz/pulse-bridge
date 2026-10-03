import Foundation

/// X axis of the Summary heart-rate chart: the last hour while live, otherwise today so far.
public enum HeartRateChartRange {
    public static let liveSpan: TimeInterval = 3600

    /// Today's range is at least an hour wide, so just after midnight the axis isn't a sliver.
    public static func domain(live: Bool, now: Date, calendar: Calendar) -> ClosedRange<Date> {
        if live { return now.addingTimeInterval(-liveSpan)...now }
        let midnight = calendar.startOfDay(for: now)
        return midnight...max(now, midnight.addingTimeInterval(liveSpan))
    }
}
