import Foundation

/// Decides when the band buzzes during an activity with a target zone: after 15 s outside the zone,
/// then at most once a minute while still outside in the same direction.
public struct ZoneAlert: Sendable, Equatable {
    public enum Direction: Sendable, Equatable { case above, below }

    public static let threshold: TimeInterval = 15
    public static let repeatAfter: TimeInterval = 60
    /// A heart-rate gap longer than this (band dropped out) starts the timing over.
    public static let stale: TimeInterval = 10

    public let target: ClosedRange<Int>
    private var direction: Direction?
    private var outsideSince: Date?
    private var lastAlert: Date?
    private var lastReading: Date?

    public init(target: ClosedRange<Int>) {
        self.target = target
    }

    /// Above 3 buzzes, below 2 (2 was easy to miss in a test; change here if it isn't felt).
    public static func buzzes(for direction: Direction) -> Int {
        direction == .above ? 3 : 2
    }

    public mutating func update(bpm: Int, at date: Date) -> Direction? {
        if let lastReading, date.timeIntervalSince(lastReading) > Self.stale { reset() }
        lastReading = date
        let now: Direction? = bpm > target.upperBound ? .above : bpm < target.lowerBound ? .below : nil
        guard let now else {
            direction = nil
            outsideSince = nil
            lastAlert = nil
            return nil
        }
        if now != direction {
            direction = now
            outsideSince = date
            lastAlert = nil
        }
        guard let outsideSince, date.timeIntervalSince(outsideSince) >= Self.threshold else { return nil }
        if let lastAlert, date.timeIntervalSince(lastAlert) < Self.repeatAfter { return nil }
        lastAlert = date
        return now
    }

    public mutating func reset() {
        direction = nil
        outsideSince = nil
        lastAlert = nil
        lastReading = nil
    }
}
