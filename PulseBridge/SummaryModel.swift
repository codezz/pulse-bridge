import Foundation
import Observation
import PulseKit

/// The last 7 days for the Summary cards. Reloaded on appear and after every sync.
@MainActor
@Observable
final class SummaryModel {
    let service: SummaryService
    private(set) var metrics: DailyMetrics?
    private(set) var error: String?
    /// False until the first load finished, so cards show placeholders instead of "No data".
    var isLoaded: Bool { metrics != nil || error != nil }

    init(service: SummaryService) {
        self.service = service
    }

    func reload() {
        do {
            metrics = try service.load(days: 7, endingOn: .now)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
