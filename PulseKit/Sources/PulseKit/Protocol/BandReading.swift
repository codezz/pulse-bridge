/// Decoded record values. Byte offsets match docs/protocol.md and the JStyle 2025 SDK.
public enum BandReading: Sendable, Equatable {
    case dailyTotals(steps: Int, distanceMeters: Int)
    case activity(steps: Int, distanceMeters: Int, minuteSteps: [Int])
    case sleep(minuteStages: [Int])
    case continuousHR(minuteBPM: [Int])
    case spotHR(bpm: Int)
    case hrv(ms: Int, heartRate: Int, stress: Int, systolic: Int, diastolic: Int)
    case spo2(percent: Int)
    case workout(WorkoutInfo)

    init(kind: HistoryKind, bytes b: [UInt8]) {
        switch kind {
        case .dailyTotals:
            self = .dailyTotals(steps: littleEndian(b, at: 5, count: 4),
                                distanceMeters: littleEndian(b, at: 13, count: 4) * 10)
        case .activity:
            self = .activity(steps: littleEndian(b, at: 9, count: 2),
                             distanceMeters: littleEndian(b, at: 13, count: 2) * 10,
                             minuteSteps: b[15..<25].map(Int.init))
        case .sleep:
            let count = min(Int(b[9]), kind.recordSize - 10)
            self = .sleep(minuteStages: b[10..<10 + count].map(Int.init))
        case .continuousHR:
            self = .continuousHR(minuteBPM: b[9..<24].map(Int.init))
        case .spotHR:
            self = .spotHR(bpm: Int(b[9]))
        case .hrv:
            // b[10] is "vascular aging" in the SDK; not used.
            self = .hrv(ms: Int(b[9]), heartRate: Int(b[11]), stress: Int(b[12]),
                        systolic: Int(b[13]), diastolic: Int(b[14]))
        case .spo2:
            self = .spo2(percent: Int(b[9]))
        case .workout:
            // Corrupt floats (NaN, infinity, absurd values) read as 0 instead of trapping.
            let float = { (offset: Int) -> Double in
                let value = Double(Float(bitPattern: UInt32(littleEndian(b, at: offset, count: 4))))
                return value.isFinite && value >= 0 && value < 100_000 ? value : 0
            }
            self = .workout(WorkoutInfo(activity: WorkoutActivity(bandMode: Int(b[9])), heartRate: Int(b[10]),
                                        seconds: littleEndian(b, at: 11, count: 2), steps: littleEndian(b, at: 13, count: 2),
                                        calories: float(17).rounded(), distanceMeters: Int((float(21) * 1000).rounded())))
        }
    }
}

/// Workout type. Mode numbers follow the JStyle SDK's sport list; only 9 (walking) has been seen on this band.
public enum WorkoutActivity: String, Sendable, Equatable, CaseIterable, Codable {
    case running, cycling, walking, hiking, other

    public init(bandMode: Int) {
        switch bandMode {
        case 0: self = .running
        case 1: self = .cycling
        case 9: self = .walking
        case 12: self = .hiking
        default: self = .other
        }
    }
}

public struct WorkoutInfo: Sendable, Equatable {
    public let activity: WorkoutActivity
    /// Average heart rate during the workout.
    public let heartRate: Int
    public let seconds: Int
    public let steps: Int
    public let calories: Double
    public let distanceMeters: Int
}
