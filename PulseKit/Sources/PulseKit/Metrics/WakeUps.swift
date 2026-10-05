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
    /// Sources: docs/superpowers/specs and the chat research (Basner ECG arousal algorithm,
    /// Perez-Pozuelo 2022), adapted to a reading every ~5 minutes.
    public static func estimatedWakeUps(_ night: SleepNight, heartRate: [Reading]) -> [EstimatedWakeUp] {
        let during = heartRate.filter { $0.date >= night.fellAsleep && $0.date <= night.wokeUp }
        guard during.count >= minimumReadings else { return [] }
        let sorted = during.map(\.value).sorted()
        let median = sorted[sorted.count / 2]
        let from = night.fellAsleep.addingTimeInterval(edgeMinutes), to = night.wokeUp.addingTimeInterval(-edgeMinutes)

        var result: [EstimatedWakeUp] = []
        for reading in during where reading.value >= median + wakeRise && reading.date >= from && reading.date <= to {
            guard let reason = reason(at: reading.date, rise: reading.value - median, night.segments) else { continue }
            if let last = result.last, reading.date.timeIntervalSince(last.date) < mergeWindow { continue }
            result.append(EstimatedWakeUp(date: reading.date, bpm: Int(reading.value.rounded()), reason: reason))
        }
        return result
    }

    private static func reason(at date: Date, rise: Double, _ segments: [SleepNight.Segment]) -> EstimatedWakeUp.Reason? {
        let stage = segments.first { $0.start <= date && date < $0.end }?.stage
        // Stage changes (from -> to) within the window around the reading.
        let changes = zip(segments, segments.dropFirst())
            .filter { $0.0.stage != $0.1.stage && abs($0.1.start.timeIntervalSince(date)) <= stageWindow }
            .map { (from: $0.0.stage, to: $0.1.stage) }
        let awakeNear = segments.contains { $0.stage == .awake && $0.start <= date.addingTimeInterval(stageWindow)
            && $0.end >= date.addingTimeInterval(-stageWindow) }
        if stage == .rem || changes.contains(where: { $0.to == .rem }) {
            return rise >= dreamCeiling ? .highHeartRate : nil
        }
        if stage == .awake || awakeNear { return .awake }
        if changes.contains(where: { $0.from == .rem }) { return .outOfREM }
        if changes.contains(where: { $0.from == .deep }) { return .outOfDeepSleep }
        return rise >= dreamCeiling ? .highHeartRate : nil
    }
}
