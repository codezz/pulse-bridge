import Foundation

/// Oura-style sleep score with a published, transparent formula (an estimate, not Oura's).
/// Ranges follow the NSF sleep quality consensus (Ohayon 2017) and AASM durations; stage contributors
/// carry little weight because wrist bands stage deep/REM poorly (Schyvens 2025). Details in the
/// private research notes and in the in-app info sheet.
public struct SleepScore: Sendable, Equatable {
    public enum Contributor: String, CaseIterable, Sendable {
        case totalSleep, efficiency, restfulness, regularity, latency, rem, deep

        public var weight: Int {
            switch self {
            case .totalSleep: 35
            case .efficiency, .restfulness, .regularity: 15
            case .latency: 10
            case .rem, .deep: 5
            }
        }
    }

    /// Nights shorter than this score at most `shortNightCap`, whatever the other contributors say.
    public static let shortNight = 6 * 60
    public static let shortNightCap = 70
    /// Regularity needs this many previous nights; with fewer it uses the 00:00-03:00 clock window.
    public static let minimumHistory = 3

    public let contributors: [Contributor: Int]
    public let value: Int
    /// Median sleep midpoint of the previous nights, in minutes after midnight (nil without history).
    public let usualMidpoint: Int?
    public var label: String { Self.label(for: value) }

    public static func label(for value: Int) -> String {
        switch value {
        case 85...: "Optimal"
        case 70..<85: "Good"
        case 60..<70: "Fair"
        default: "Pay attention"
        }
    }

    /// `recentMidpoints`: midpoints of up to 14 previous nights, for the regularity contributor.
    public init(night: SleepNight, calendar: Calendar, recentMidpoints: [Date] = []) {
        let hours = Double(night.asleep) / 60
        let latency = Double(night.latency)
        let rem = night.share(.rem) * 100
        let usual = Self.usualMidpoint(recentMidpoints, calendar: calendar)
        let midpoint = Self.clockMinutes(night.midpoint, calendar: calendar)
        let values: [Contributor: Double] = [
            .totalSleep: hours <= 9 ? Self.ramp(hours, zeroAt: 4, fullAt: 7)
                : hours <= 10 ? 100 : max(0, 100 - 10 * (hours - 10)),
            .efficiency: Self.ramp(night.efficiency * 100, zeroAt: 70, fullAt: 90),
            .restfulness: (Self.ramp(Double(night.awakeAfterOnset), zeroAt: 60, fullAt: 20)
                + Self.ramp(Double(night.longAwakenings), zeroAt: 4, fullAt: 1)) / 2,
            .regularity: usual.map { Self.ramp(Double(Self.clockDistance(midpoint, $0)), zeroAt: 120, fullAt: 30) }
                ?? Self.ramp(Self.minutesOutsideWindow(night.midpoint, calendar: calendar), zeroAt: 240, fullAt: 0),
            .latency: latency < 5 ? 85 : latency <= 30 ? 100 : Self.ramp(latency, zeroAt: 60, fullAt: 30),
            .rem: rem < 21 ? Self.ramp(rem, zeroAt: 5, fullAt: 21) : rem <= 40 ? 100 : Self.ramp(rem, zeroAt: 50, fullAt: 40),
            .deep: Self.ramp(night.share(.deep) * 100, zeroAt: 3, fullAt: 16),
        ]
        contributors = values.mapValues { Int($0.rounded()) }
        usualMidpoint = usual
        let total = Contributor.allCases.reduce(0.0) { $0 + values[$1]! * Double($1.weight) / 100 }
        let weighted = Int(total.rounded())
        value = night.asleep < Self.shortNight ? min(weighted, Self.shortNightCap) : weighted
    }

    /// 0 at `zeroAt`, 100 at `fullAt` (either direction), linear in between, clamped.
    static func ramp(_ x: Double, zeroAt: Double, fullAt: Double) -> Double {
        let t = (x - zeroAt) / (fullAt - zeroAt)
        return min(100, max(0, t * 100))
    }

    /// Clock time in minutes after midnight (by clock, so daylight-saving nights aren't shifted).
    static func clockMinutes(_ date: Date, calendar: Calendar) -> Int {
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        return clock.hour! * 60 + clock.minute!
    }

    /// Minutes between two clock times, the short way round midnight.
    static func clockDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % (24 * 60)
        return min(d, 24 * 60 - d)
    }

    /// Median clock time on a noon-to-noon scale, so 23:50 and 00:10 average to 00:00.
    static func usualMidpoint(_ midpoints: [Date], calendar: Calendar) -> Int? {
        guard midpoints.count >= minimumHistory else { return nil }
        let afterNoon = midpoints.map { (clockMinutes($0, calendar: calendar) + 12 * 60) % (24 * 60) }.sorted()
        let middle = afterNoon.count / 2
        let median = afterNoon.count.isMultiple(of: 2) ? (afterNoon[middle - 1] + afterNoon[middle]) / 2 : afterNoon[middle]
        return (median + 12 * 60) % (24 * 60)
    }

    /// Distance of the sleep midpoint from the 00:00-03:00 window, in minutes, by clock time.
    static func minutesOutsideWindow(_ midpoint: Date, calendar: Calendar) -> Double {
        var minutes = Double(clockMinutes(midpoint, calendar: calendar))
        if minutes >= 12 * 60 { minutes -= 24 * 60 } // 23:30 -> -30
        return minutes < 0 ? -minutes : max(0, minutes - 180)
    }
}
