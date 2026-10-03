import Foundation

/// Live heart rate: the last 10 minutes for the chart, plus whole-session statistics.
public struct HeartRateSeries: Sendable, Equatable {
    public struct Sample: Sendable, Equatable, Identifiable {
        public let date: Date
        public let bpm: Int
        /// Increments after a gap, so the chart doesn't draw a line across it.
        public var segment = 0
        public var id: Date { date }
    }

    public static let window: TimeInterval = 600
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
        samples.append(Sample(date: date, bpm: bpm, segment: segment))
        samples.removeAll { $0.date < date.addingTimeInterval(-Self.window) }
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
}
