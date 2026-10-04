import Foundation

/// Whether a background refresh should sync: the same hourly rule as opening the app, keyed on the
/// last Health export and the last attempt, and only with a paired band and nothing else running.
public enum BackgroundSync {
    public static func shouldRun(lastExport: Date?, lastAttempt: Date?, paired: Bool, busy: Bool, now: Date) -> Bool {
        paired && !busy && AutoSync.isDue(lastSync: [lastExport, lastAttempt].compactMap { $0 }.max(), now: now)
    }
}
