import Foundation

/// Karvonen (heart-rate reserve) zones: lower bounds at 50/60/70/80/90% of (max - resting) above resting.
public struct HeartRateZones: Codable, Sendable, Equatable {
    public let max: Int
    public let resting: Int
    static let lowerPercent: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]

    public init(max: Int, resting: Int) {
        self.max = max
        self.resting = resting
    }

    public func lowerBound(of zone: Int) -> Int {
        Int((Double(resting) + Self.lowerPercent[zone - 1] * Double(max - resting)).rounded())
    }

    public func range(of zone: Int) -> ClosedRange<Int> {
        lowerBound(of: zone)...(zone == 5 ? max : lowerBound(of: zone + 1) - 1)
    }

    /// 0 below zone 1.
    public func zone(for bpm: Int) -> Int {
        (1...5).last { bpm >= lowerBound(of: $0) } ?? 0
    }
}

/// Max and resting heart rate from the user's own data, recomputed at every activity start.
public struct HeartRateProfile: Sendable, Equatable {
    public enum MaxSource: Sendable, Equatable { case age, measured }

    public static let defaultResting = 60
    public static let lookBack: TimeInterval = 180 * 86400
    /// A max must be held: the third-highest reading in any window this long.
    public static let sustainedWindow: TimeInterval = 180
    public static let minimumNights = 3

    public let max: Int
    public let maxSource: MaxSource
    public let resting: Int
    public let restingIsDefault: Bool
    public var zones: HeartRateZones { HeartRateZones(max: max, resting: resting) }

    /// Tanaka 2001: 208 - 0.7 x age.
    public static func tanaka(age: Int) -> Int {
        Int((208 - 0.7 * Double(age)).rounded())
    }

    /// Per-minute medians of second-by-second readings (recorded activities), so short optical
    /// artifacts can't count as a sustained max.
    public static func minuteMedians(_ readings: [Reading]) -> [Reading] {
        Dictionary(grouping: readings) { ($0.date.timeIntervalSinceReferenceDate / 60).rounded(.down) }
            .map { minute, values in
                let sorted = values.map(\.value).sorted()
                return Reading(date: Date(timeIntervalSinceReferenceDate: minute * 60), value: sorted[sorted.count / 2])
            }
            .sorted { $0.date < $1.date }
    }

    public static func sustainedMax(_ readings: [Reading], since: Date) -> Int? {
        let recent = readings.filter { $0.date >= since }.sorted { $0.date < $1.date }
        var best: Int?
        for (i, reading) in recent.enumerated() {
            let window = recent[i...].prefix { $0.date < reading.date.addingTimeInterval(sustainedWindow) }.map(\.value)
            guard window.count >= 3 else { continue }
            let third = Int(window.sorted(by: >)[2])
            best = Swift.max(best ?? 0, third)
        }
        return best
    }

    /// `heartRate`: stored readings (band history and recorded activities); `nightlyResting`: the last 14 nights.
    public init(age: Int, heartRate: [Reading], nightlyResting: [Int], now: Date) {
        let byAge = Self.tanaka(age: age)
        let measured = Self.sustainedMax(heartRate, since: now.addingTimeInterval(-Self.lookBack)) ?? 0
        max = Swift.max(byAge, measured)
        maxSource = measured > byAge ? .measured : .age
        if nightlyResting.count >= Self.minimumNights {
            let sorted = nightlyResting.sorted()
            let mid = sorted.count / 2
            resting = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
            restingIsDefault = false
        } else {
            resting = Self.defaultResting
            restingIsDefault = true
        }
    }
}
