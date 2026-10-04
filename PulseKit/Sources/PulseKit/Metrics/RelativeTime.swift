import Foundation

/// "just now", "5 min ago", "2 h ago", then "yesterday" / "3 days ago" by calendar day.
/// Dates in the future (clock skew) read "just now".
public enum RelativeTime {
    public static func text(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86400: return "\(Int(seconds / 3600)) h ago"
        default:
            // Calendar days: at 00:30, a sync 25 h earlier was the day before yesterday.
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
            return days <= 1 ? "yesterday" : "\(days) days ago"
        }
    }
}
