import Foundation

public struct Reading: Sendable, Equatable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Timestamped values from stored band records; zero values (no measurement) are skipped.
public struct Readings: Sendable {
    public private(set) var heartRate: [Reading] = []
    public private(set) var hrv: [Reading] = []
    public private(set) var spo2: [Reading] = []
    /// Steps per minute (from the 10-minute activity blocks).
    public private(set) var steps: [Reading] = []
    /// Meters per 10-minute activity block, at the block start.
    public private(set) var distance: [Reading] = []
    /// Workouts recorded by the band, oldest first.
    public private(set) var workouts: [Workout] = []
    /// Minute start -> the band's stage for that minute (awake minutes included).
    public private(set) var sleepStages: [Date: SleepStage] = [:]

    public init(records: [HistoryRecord]) {
        for record in records {
            let minute = { (offset: Int) in record.start.addingTimeInterval(Double(offset) * 60) }
            switch record.reading {
            case let .spotHR(bpm) where bpm > 0:
                heartRate.append(Reading(date: record.start, value: Double(bpm)))
            case let .continuousHR(minuteBPM):
                for (offset, bpm) in minuteBPM.enumerated() where bpm > 0 {
                    heartRate.append(Reading(date: minute(offset), value: Double(bpm)))
                }
            case let .hrv(ms, _, _, _, _) where ms > 0:
                hrv.append(Reading(date: record.start, value: Double(ms)))
            case let .spo2(percent) where percent > 0:
                spo2.append(Reading(date: record.start, value: Double(percent)))
            case let .activity(_, distanceMeters, minuteSteps):
                for (offset, count) in minuteSteps.enumerated() where count > 0 {
                    steps.append(Reading(date: minute(offset), value: Double(count)))
                }
                if distanceMeters > 0 { distance.append(Reading(date: record.start, value: Double(distanceMeters))) }
            case let .workout(info) where info.seconds > 0:
                workouts.append(Workout(start: record.start, info: info))
            case let .sleep(stages):
                for (offset, value) in stages.enumerated() {
                    if let stage = SleepStage(bandValue: value) {
                        let key = Self.minuteStart(minute(offset))
                        // Overlapping records: an asleep stage wins over awake, whatever the order.
                        if stage != .awake || sleepStages[key] == nil { sleepStages[key] = stage }
                    }
                }
            default:
                break
            }
        }
        heartRate.sort { $0.date < $1.date }
        hrv.sort { $0.date < $1.date }
        spo2.sort { $0.date < $1.date }
        steps.sort { $0.date < $1.date }
        distance.sort { $0.date < $1.date }
        workouts.sort { $0.start < $1.start }
    }

    public func isAsleep(at date: Date) -> Bool {
        guard let stage = sleepStages[Self.minuteStart(date)] else { return false }
        return stage != .awake
    }

    private static func minuteStart(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}

public struct Workout: Sendable, Equatable, Identifiable {
    public let start: Date
    public let info: WorkoutInfo
    public var id: Date { start }
    public var end: Date { start.addingTimeInterval(Double(info.seconds)) }
}
