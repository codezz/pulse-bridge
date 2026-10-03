import Foundation

/// Live heart rate: the last hour for the chart, plus whole-session statistics.
public struct HeartRateSeries: Sendable, Equatable {
    public struct Sample: Sendable, Equatable, Identifiable {
        public let date: Date
        public let bpm: Int
        /// Increments after a gap, so the chart doesn't draw a line across it.
        public var segment = 0
        public var id: Date { date }
    }

    /// A stretch of one zone, drawn as its own line. A run that ends because the zone changed also
    /// holds the next sample, so the line stays connected.
    public struct ZoneRun: Sendable, Equatable, Identifiable {
        public let id: Int
        public let zone: Int
        public var samples: [Sample]
    }

    public static let window: TimeInterval = 3600
    /// Kept samples are this far apart; the newest reading replaces the last point until then,
    /// so an hour is about 720 points.
    static let spacing: TimeInterval = 5
    /// The band repeats its last value when it is off the wrist (seen 2026-10-02).
    public static let staleAfter: TimeInterval = 120
    /// Samples further apart than this (app was closed, band disconnected) start a fresh stretch.
    static let gapAfter: TimeInterval = 5

    public private(set) var samples: [Sample] = []
    private var sessionMin: Int?
    private var sessionMax: Int?
    private var sum = 0
    private var count = 0
    private var lastChange: Date?

    public init() {}

    public mutating func append(_ bpm: Int, at date: Date) {
        guard bpm > 0 else { return }
        let afterGap = samples.last.map { date.timeIntervalSince($0.date) > Self.gapAfter } ?? true
        if afterGap || samples.last?.bpm != bpm { lastChange = date }
        let segment = (samples.last?.segment ?? 0) + (afterGap && !samples.isEmpty ? 1 : 0)
        let sample = Sample(date: date, bpm: bpm, segment: segment)
        if !afterGap, samples.count >= 2,
           samples[samples.count - 2].segment == segment,
           samples[samples.count - 1].date.timeIntervalSince(samples[samples.count - 2].date) < Self.spacing {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }
        let cutoff = date.addingTimeInterval(-Self.window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }) { samples.removeFirst(firstKept) }
        sessionMin = min(sessionMin ?? bpm, bpm)
        sessionMax = max(sessionMax ?? bpm, bpm)
        sum += bpm
        count += 1
    }

    public var latest: Int? { samples.last?.bpm }
    public var minimum: Int? { sessionMin }
    public var maximum: Int? { sessionMax }
    public var average: Int? { count > 0 ? Int((Double(sum) / Double(count)).rounded()) : nil }

    public func isStale(now: Date) -> Bool {
        guard let lastChange else { return false }
        return now.timeIntervalSince(lastChange) >= Self.staleAfter
    }

    /// `since`: the chart's start; older samples would draw outside the plot.
    public func zoneRuns(_ zones: HeartRateZones, since: Date = .distantPast) -> [ZoneRun] {
        var runs: [ZoneRun] = []
        for sample in samples where sample.date >= since {
            let zone = zones.zone(for: sample.bpm)
            let sameSegment = runs.last?.samples.last?.segment == sample.segment
            if sameSegment, runs.last?.zone == zone {
                runs[runs.count - 1].samples.append(sample)
                continue
            }
            if sameSegment { runs[runs.count - 1].samples.append(sample) }   // connect into the next zone
            runs.append(ZoneRun(id: runs.count, zone: zone, samples: [sample]))
        }
        return runs
    }
}
