import Foundation

public enum HealthMetric: String, CaseIterable, Sendable {
    case steps, distance, heartRate, hrv, oxygenSaturation
    /// Category sample; `HealthSample.value` holds a `SleepStage` raw value.
    case sleep
    /// A workout; `HealthSample.workout` holds its details, `value` its calories.
    case workout
}

/// Apple Health sleep stages. The band's 1 vs 3 split is an estimate (see docs/protocol.md).
public enum SleepStage: Int, Sendable {
    case awake, core, deep, rem

    public init?(bandValue: Int) {
        switch bandValue {
        case 1: self = .rem
        case 2: self = .core
        case 3: self = .deep
        case 4, 5: self = .awake
        default: return nil
        }
    }
}

/// A HealthKit-ready value, independent of HealthKit so it can be tested on macOS.
public struct HealthSample: Sendable, Equatable {
    public let metric: HealthMetric
    public let start: Date
    public let end: Date
    /// Steps, meters, bpm, milliseconds, a 0...1 fraction for oxygen saturation, or a SleepStage raw value.
    public let value: Double
    public let syncID: String
    /// HealthKit sync version: a higher value replaces the sample with the same sync ID.
    public var version = 1
    /// Set for `.workout` samples.
    public var workout: WorkoutInfo?
}

extension HistoryKind {
    /// Daily totals duplicate the activity detail, so they stay on the phone.
    public var exportsToHealth: Bool { self != .dailyTotals }
}

extension HistoryRecord {
    /// Built from the raw BCD timestamp, so it stays the same if the phone changes time zone.
    public func id(serial: String) -> String {
        "\(serial).\([kind.rawValue].hex()).\([UInt8](raw)[kind.timestampRange].hex())"
    }

    public func healthSamples(id: String, version: Int = 1) -> [HealthSample] {
        samples(id: id).map { sample in
            var sample = sample
            sample.version = version
            return sample
        }
    }

    private func samples(id: String) -> [HealthSample] {
        switch reading {
        case let .activity(_, distanceMeters, minuteSteps):
            let steps = series(.steps, minuteSteps, id: id, lastsAMinute: true)
            guard distanceMeters > 0 else { return steps }
            return steps + [HealthSample(metric: .distance, start: start, end: minute(minuteSteps.count),
                                         value: Double(distanceMeters), syncID: "\(id).d")]
        case let .continuousHR(minuteBPM):
            return series(.heartRate, minuteBPM, id: id, lastsAMinute: false)
        case let .spotHR(bpm):
            return point(.heartRate, bpm, id: id)
        case let .hrv(ms, _, _, _, _):
            return point(.hrv, ms, id: id)
        case let .spo2(percent):
            return point(.oxygenSaturation, percent, id: id, divisor: 100)
        case let .sleep(minuteStages):
            return sleepRuns(minuteStages, id: id)
        case let .workout(info):
            guard info.seconds > 0 else { return [] }
            var sample = HealthSample(metric: .workout, start: start, end: start.addingTimeInterval(Double(info.seconds)),
                                      value: info.calories, syncID: id)
            sample.workout = info
            return [sample]
        case .dailyTotals:
            return []
        }
    }

    private func minute(_ offset: Int) -> Date {
        start.addingTimeInterval(Double(offset) * 60)
    }

    /// One sample per minute that has a value; zero means "not measured".
    private func series(_ metric: HealthMetric, _ values: [Int], id: String, lastsAMinute: Bool) -> [HealthSample] {
        values.enumerated().compactMap { offset, value in
            guard value > 0 else { return nil }
            return HealthSample(metric: metric, start: minute(offset), end: minute(lastsAMinute ? offset + 1 : offset),
                                value: Double(value), syncID: "\(id).\(offset)")
        }
    }

    /// One sample per run of the same stage; unknown values end a run and are skipped.
    private func sleepRuns(_ values: [Int], id: String) -> [HealthSample] {
        guard !values.isEmpty else { return [] }
        var samples: [HealthSample] = []
        var runStart = 0
        for offset in 1...values.count where offset == values.count || values[offset] != values[runStart] {
            if let stage = SleepStage(bandValue: values[runStart]) {
                samples.append(HealthSample(metric: .sleep, start: minute(runStart), end: minute(offset),
                                            value: Double(stage.rawValue), syncID: "\(id).\(runStart)"))
            }
            runStart = offset
        }
        return samples
    }

    private func point(_ metric: HealthMetric, _ value: Int, id: String, divisor: Double = 1) -> [HealthSample] {
        guard value > 0 else { return [] }
        return [HealthSample(metric: metric, start: start, end: start, value: Double(value) / divisor, syncID: id)]
    }
}
