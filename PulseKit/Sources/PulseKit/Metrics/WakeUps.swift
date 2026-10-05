import Foundation

/// A moment the night's heart rate and the band's stages suggest a brief waking. An estimate: the band
/// itself rarely marks awake minutes during the night (it judges sleep from wrist movement).
public struct EstimatedWakeUp: Sendable, Equatable, Identifiable {
    public enum Reason: String, Sendable {
        /// A heart-rate rise as a sleep cycle ends.
        case outOfREM
        /// A rise while the band itself says awake.
        case awake
        /// A rise with an abrupt lift out of deep sleep.
        case outOfDeepSleep
        /// A rise too large for a dream (25+ bpm over the night's typical value).
        case highHeartRate
    }

    public let date: Date
    public let bpm: Int
    public let reason: Reason
    public var id: Date { date }
}

extension SleepAnalysis {
    /// A rise of this much over the night's median heart rate is worth a look.
    static let wakeRise = 10.0
    /// Larger than this is too much for REM dreaming.
    static let dreamCeiling = 25.0
    /// Falling asleep and waking up aren't wake-ups.
    static let edgeMinutes: TimeInterval = 15 * 60
    /// Stage changes this close count as "at the same time".
    static let stageWindow: TimeInterval = 5 * 60
    /// Rises closer than this are one wake-up.
    static let mergeWindow: TimeInterval = 10 * 60
    static let minimumReadings = 10

    /// Heart-rate rises (10+ bpm over the night's median) that the band's stages explain: coming out of
    /// REM, while awake, or out of deep sleep. Rises in or into REM are taken as dreams unless 25+ bpm.
    /// Adapted from the Basner ECG arousal algorithm and Perez-Pozuelo et al. 2022 to a reading every
    /// ~5 minutes.
    public static func estimatedWakeUps(_ night: SleepNight, heartRate: [Reading]) -> [EstimatedWakeUp] {
        let during = heartRate.filter { $0.date >= night.fellAsleep && $0.date <= night.wokeUp }
        guard during.count >= minimumReadings else { return [] }
        let sorted = during.map(\.value).sorted()
        let median = sorted[sorted.count / 2]
        let from = night.fellAsleep.addingTimeInterval(edgeMinutes), to = night.wokeUp.addingTimeInterval(-edgeMinutes)

        var result: [EstimatedWakeUp] = []
        var lastRise: Date?
        for reading in during where reading.value >= median + wakeRise && reading.date >= from && reading.date <= to {
            // Rises less than 10 min after the previous one of a wake-up belong to it; keep its peak.
            if let previous = lastRise, reading.date.timeIntervalSince(previous) < mergeWindow, let current = result.last {
                if reading.value > Double(current.bpm) {
                    result[result.count - 1] = EstimatedWakeUp(date: current.date, bpm: Int(reading.value.rounded()), reason: current.reason)
                }
                lastRise = reading.date
                continue
            }
            guard let reason = reason(at: reading.date, rise: reading.value - median, night) else { continue }
            result.append(EstimatedWakeUp(date: reading.date, bpm: Int(reading.value.rounded()), reason: reason))
            lastRise = reading.date
        }
        return result
    }

    private static func reason(at date: Date, rise: Double, _ night: SleepNight) -> EstimatedWakeUp.Reason? {
        let segments = night.segments
        let window = DateInterval(start: date.addingTimeInterval(-stageWindow), end: date.addingTimeInterval(stageWindow))
        let stage = segments.first { $0.start <= date && date < $0.end }?.stage
        // Stage changes (from -> to) within the window, nearest to the reading first: when REM
        // switches on and off around a reading, the closest change decides dream vs end of cycle.
        let changes = zip(segments, segments.dropFirst())
            .filter { $0.0.stage != $0.1.stage && window.contains($0.1.start) }
            .sorted { abs($0.1.start.timeIntervalSince(date)) < abs($1.1.start.timeIntervalSince(date)) }
            .map { (from: $0.0.stage, to: $0.1.stage) }
        // Awake as the band recorded it, not minutes filled in where data is missing.
        let bandAwake = segments.contains { segment in
            segment.stage == .awake && segment.start < window.end && segment.end > window.start
                && !night.gaps.contains { $0.start <= segment.start && $0.end >= segment.end }
        }
        if bandAwake { return .awake }
        if let nearest = changes.first {
            if nearest.from == .rem { return .outOfREM }
            if nearest.to == .rem { return rise >= dreamCeiling ? .highHeartRate : nil }
        } else if stage == .rem {
            return rise >= dreamCeiling ? .highHeartRate : nil
        }
        if changes.contains(where: { $0.from == .deep }) { return .outOfDeepSleep }
        return rise >= dreamCeiling ? .highHeartRate : nil
    }
}
