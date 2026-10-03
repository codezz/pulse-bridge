import Foundation

public struct SleepMinute: Sendable, Equatable {
    public let date: Date
    public let stage: SleepStage
}

/// One night of sleep (rules: docs/superpowers/specs/2026-10-02-sleep-section-design.md).
public struct SleepNight: Sendable, Equatable {
    public struct Segment: Sendable, Equatable, Identifiable {
        public let start: Date
        public let end: Date
        public let stage: SleepStage
        public var id: Date { start }
    }

    public let inBedStart: Date
    public let inBedEnd: Date
    public let fellAsleep: Date
    public let wokeUp: Date
    /// Minutes per stage over the whole session (awake includes falling asleep and after waking).
    public let minutes: [SleepStage: Int]
    /// Awake minutes between falling asleep and waking up.
    public let awakeAfterOnset: Int
    /// Awake stretches of at least 2 minutes between falling asleep and waking up.
    public let awakenings: Int
    /// Awake stretches of at least 5 minutes between falling asleep and waking up (NSF's measure).
    public let longAwakenings: Int
    public let segments: [Segment]

    public init(inBedStart: Date, inBedEnd: Date, fellAsleep: Date, wokeUp: Date, minutes: [SleepStage: Int],
                awakeAfterOnset: Int, awakenings: Int, longAwakenings: Int = 0, segments: [Segment]) {
        self.inBedStart = inBedStart
        self.inBedEnd = inBedEnd
        self.fellAsleep = fellAsleep
        self.wokeUp = wokeUp
        self.minutes = minutes
        self.awakeAfterOnset = awakeAfterOnset
        self.awakenings = awakenings
        self.longAwakenings = longAwakenings
        self.segments = segments
    }

    public var inBed: Int { Int(inBedEnd.timeIntervalSince(inBedStart) / 60) }
    public var asleep: Int { [SleepStage.core, .deep, .rem].reduce(0) { $0 + (minutes[$1] ?? 0) } }
    public var latency: Int { Int(fellAsleep.timeIntervalSince(inBedStart) / 60) }
    public var efficiency: Double { inBed > 0 ? Double(asleep) / Double(inBed) : 0 }
    public var midpoint: Date { fellAsleep.addingTimeInterval(wokeUp.timeIntervalSince(fellAsleep) / 2) }

    /// Share of asleep time spent in a stage.
    public func share(_ stage: SleepStage) -> Double {
        asleep > 0 ? Double(minutes[stage] ?? 0) / Double(asleep) : 0
    }
}

public enum SleepAnalysis {
    /// Gaps in the band's sleep data up to this long stay in the same session.
    public static let mergeGap: TimeInterval = 3600
    /// Awake stretches shorter than this are blips, not awakenings.
    static let awakeningMinutes = 2
    static let longAwakeningMinutes = 5

    /// Consecutive sleep minutes, oldest first, split where the data stops for more than `mergeGap`.
    public static func sessions(_ stages: [Date: SleepStage]) -> [[SleepMinute]] {
        let minutes = stages.map { SleepMinute(date: $0.key, stage: $0.value) }.sorted { $0.date < $1.date }
        var sessions: [[SleepMinute]] = []
        for minute in minutes {
            if let last = sessions.last?.last, minute.date.timeIntervalSince(last.date) - 60 <= mergeGap {
                sessions[sessions.count - 1].append(minute)
            } else {
                sessions.append([minute])
            }
        }
        return sessions
    }

    /// The session ending inside `window` with the most asleep minutes.
    public static func night(in window: DateInterval, stages: [Date: SleepStage]) -> SleepNight? {
        night(in: window, sessions: sessions(stages))
    }

    /// Same, over sessions computed once (DailyMetrics reuses them for every day).
    public static func night(in window: DateInterval, sessions: [[SleepMinute]]) -> SleepNight? {
        sessions
            .filter { session in
                let end = session.last!.date.addingTimeInterval(60)
                return end > window.start && end <= window.end
            }
            .compactMap(night(from:))
            .max { $0.asleep < $1.asleep }
    }

    public static func night(from rawSession: [SleepMinute]) -> SleepNight? {
        let session = fillingGaps(rawSession)
        guard let first = session.first, let last = session.last,
              let onset = session.firstIndex(where: { $0.stage != .awake }),
              let lastAsleep = session.lastIndex(where: { $0.stage != .awake }) else { return nil }
        var minutes: [SleepStage: Int] = [:]
        session.forEach { minutes[$0.stage, default: 0] += 1 }
        let middle = session[onset...lastAsleep]
        let awakeAfterOnset = middle.filter { $0.stage == .awake }.count
        let segments = segments(of: session)
        let awake = segments.filter {
            $0.stage == .awake && $0.start > session[onset].date && $0.end <= session[lastAsleep].date
        }.map { Int($0.end.timeIntervalSince($0.start) / 60) }
        let awakenings = awake.filter { $0 >= awakeningMinutes }.count
        let longAwakenings = awake.filter { $0 >= longAwakeningMinutes }.count
        return SleepNight(inBedStart: first.date, inBedEnd: last.date.addingTimeInterval(60),
                          fellAsleep: session[onset].date, wokeUp: session[lastAsleep].date.addingTimeInterval(60),
                          minutes: minutes, awakeAfterOnset: awakeAfterOnset, awakenings: awakenings,
                          longAwakenings: longAwakenings, segments: segments)
    }

    /// Minutes missing inside a session count as awake, so stage minutes always add up to time in bed.
    static func fillingGaps(_ session: [SleepMinute]) -> [SleepMinute] {
        var result: [SleepMinute] = []
        for minute in session {
            if let last = result.last {
                var next = last.date.addingTimeInterval(60)
                while next < minute.date {
                    result.append(SleepMinute(date: next, stage: .awake))
                    next = next.addingTimeInterval(60)
                }
            }
            result.append(minute)
        }
        return result
    }

    /// Runs of the same stage; a gap in the data also ends a run.
    private static func segments(of session: [SleepMinute]) -> [SleepNight.Segment] {
        var result: [SleepNight.Segment] = []
        for minute in session {
            let end = minute.date.addingTimeInterval(60)
            if let last = result.last, last.stage == minute.stage, last.end == minute.date {
                result[result.count - 1] = SleepNight.Segment(start: last.start, end: end, stage: last.stage)
            } else {
                result.append(SleepNight.Segment(start: minute.date, end: end, stage: minute.stage))
            }
        }
        return result
    }
}
