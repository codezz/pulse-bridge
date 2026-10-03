import Foundation

/// Opening the app syncs at most once per interval; the Sync button always syncs.
public enum AutoSync {
    public static let interval: TimeInterval = 3600

    /// A last sync in the future (phone clock changed) counts as due, so sync never stalls.
    public static func isDue(lastSync: Date?, now: Date = .now) -> Bool {
        guard let lastSync else { return true }
        let elapsed = now.timeIntervalSince(lastSync)
        return elapsed >= interval || elapsed < 0
    }
}
