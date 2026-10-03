import Foundation
import PulseKit

/// Stand-in for HealthKit: remembers every sync ID + version across runs, so repeat syncs
/// show whether the engine would create new samples, replace them, or resend identical ones.
@MainActor
final class LedgerHealth: HealthWriter {
    private(set) var new = 0
    private(set) var replaced = 0
    private(set) var repeated = 0
    private(set) var byMetric: [HealthMetric: Int] = [:]
    /// Sleep minutes per (night date, stage) written this run.
    private(set) var sleepMinutes: [String: [SleepStage: Int]] = [:]
    private var versions: [String: Int]
    private let url: URL

    init(url: URL) {
        self.url = url
        versions = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))) ?? [:]
    }

    var total: Int { versions.count }

    func requestAuthorization() async throws {}

    func save(_ samples: [HealthSample]) async throws -> Set<HealthMetric> {
        for sample in samples {
            switch versions[sample.syncID] {
            case nil: new += 1
            case let old? where sample.version > old: replaced += 1
            default: repeated += 1
            }
            versions[sample.syncID] = max(versions[sample.syncID] ?? 0, sample.version)
            byMetric[sample.metric, default: 0] += 1
            if sample.metric == .sleep, let stage = SleepStage(rawValue: Int(sample.value)) {
                let night = sample.start.addingTimeInterval(-12 * 3600).formatted(.iso8601.year().month().day())
                sleepMinutes[night, default: [:]][stage, default: 0] += Int(sample.end.timeIntervalSince(sample.start) / 60)
            }
        }
        try JSONEncoder().encode(versions).write(to: url)
        return []
    }
}
