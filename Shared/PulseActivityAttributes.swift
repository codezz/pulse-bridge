import ActivityKit
import SwiftUI

/// Live Activity for a Pulse Bridge activity (run, walk, ride) or a timed challenge session.
/// Compiled into the app (which starts and updates it) and the widget extension (which draws it).
struct PulseActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case running, walking, cycling, challenge

        var systemImage: String {
            switch self {
            case .running: "figure.run"
            case .walking: "figure.walk"
            case .cycling: "figure.outdoor.cycle"
            case .challenge: "figure.strengthtraining.traditional"
            }
        }
    }

    struct ContentState: Codable, Hashable {
        /// Start of the running clock (moved forward by paused time); nil while paused.
        var timerStart: Date?
        /// Elapsed time, shown frozen while paused.
        var elapsed: TimeInterval
        var distanceMeters: Double?
        var paceSecondsPerKm: Double?
        var heartRate: Int?
        var zone: Int?
        /// "In zone 2", "Above zone 2", or the session's reps.
        var status: String?
    }

    var kind: Kind
    var title: String
}

/// Heart-rate zone colours, shared by the app and the Live Activity.
func zoneColor(_ zone: Int) -> Color {
    switch zone {
    case 1: .blue
    case 2: .green
    case 3: .yellow
    case 4: .orange
    case 5: .red
    default: .gray
    }
}
