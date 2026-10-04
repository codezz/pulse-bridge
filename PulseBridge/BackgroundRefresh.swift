import BackgroundTasks
import PulseKit

/// The periodic background sync request. iOS decides when it actually runs.
enum BackgroundRefresh {
    static let identifier = "ro.codez.pulsebridge.sync"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AutoSync.interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
