import Foundation

public enum Metric: String, CaseIterable, Sendable, Hashable {
    case heartRate, restingHeartRate, hrv, spo2, steps, temperature
}

public struct DayRange: Sendable, Equatable {
    public let min: Double
    public let average: Double
    public let max: Double

    public init(min: Double, average: Double, max: Double) {
        self.min = min
        self.average = average
        self.max = max
    }

    init?(_ values: [Double]) {
        guard let low = values.min(), let high = values.max() else { return nil }
        self.init(min: low, average: values.reduce(0, +) / Double(values.count), max: high)
    }
}

public struct DailyValue: Sendable, Equatable, Identifiable {
    public let day: Date
    public let range: DayRange
    public var id: Date { day }

    public init(day: Date, range: DayRange) {
        self.day = day
        self.range = range
    }
}

public struct NightValue: Sendable, Identifiable {
    public let day: Date
    public let night: SleepNight
    public let score: SleepScore
    public var id: Date { day }
}

/// Per-day values from readings (rules: docs/superpowers/specs/2026-10-02-summary-charts-design.md).
public struct DailyMetrics: Sendable {
    public let readings: Readings
    /// Start of each day in the loaded range, oldest first.
    public let days: [Date]
    public let calendar: Calendar
    /// Sleep sessions, built once instead of on every `sleep(on:)` call.
    private let sleepSessions: [[SleepMinute]]

    /// Nights of the loaded days and the regularity look-back, computed once (each score needs 15).
    private let nights: [Date: SleepNight?]

    public init(readings: Readings, days: [Date], calendar: Calendar) {
        self.readings = readings
        self.days = days
        self.calendar = calendar
        let sessions = SleepAnalysis.sessions(readings.sleepStages)
        sleepSessions = sessions
        var nights: [Date: SleepNight?] = [:]
        if let first = days.first, let last = days.last {
            var day = calendar.date(byAdding: .day, value: -Self.regularityNights, to: first)!
            while day <= last {
                let start = calendar.startOfDay(for: day)
                let previous = calendar.date(byAdding: .day, value: -1, to: start)!
                let window = DateInterval(start: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previous)!,
                                          end: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start)!)
                nights[start] = SleepAnalysis.night(in: window, sessions: sessions)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
        self.nights = nights
    }

    public static func days(count: Int, endingOn last: Date, calendar: Calendar) -> [Date] {
        let end = calendar.startOfDay(for: last)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
    }

    public func dayInterval(of day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    /// D-1 18:00 to D 12:00: the night that counts for day D (by clock time, so DST days stay right).
    public func nightInterval(of day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let previous = calendar.date(byAdding: .day, value: -1, to: start)!
        return DateInterval(start: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previous)!,
                            end: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start)!)
    }

    public func restingHeartRate(on day: Date) -> Int? {
        let asleep = asleepReadings(readings.heartRate, night: day)
        let pool = asleep.count >= 3 ? asleep : inside(readings.heartRate, dayInterval(of: day))
        guard pool.count >= 3 else { return nil }
        let lowest = pool.map(\.value).sorted().prefix(Swift.max(3, pool.count / 10))
        return Int((lowest.reduce(0, +) / Double(lowest.count)).rounded())
    }

    public func hrv(on day: Date) -> Int? {
        let asleep = asleepReadings(readings.hrv, night: day)
        let pool = asleep.isEmpty ? inside(readings.hrv, dayInterval(of: day)) : asleep
        return DayRange(pool.map(\.value)).map { Int($0.average.rounded()) }
    }

    /// Average temperature while asleep that night (D-1 18:00 to D 12:00); without sleep data, the
    /// whole night window.
    public func nightTemperature(on day: Date) -> Double? {
        let asleep = asleepReadings(readings.temperature, night: day)
        let pool = asleep.isEmpty ? inside(readings.temperature, nightInterval(of: day)) : asleep
        return DayRange(pool.map(\.value))?.average
    }

    public func value(_ metric: Metric, on day: Date) -> DayRange? {
        switch metric {
        case .temperature: nightTemperature(on: day).map { DayRange([$0])! }
        case .heartRate, .spo2: DayRange(readings(metric, on: day).map(\.value))
        case .restingHeartRate: restingHeartRate(on: day).map { DayRange([Double($0)])! }
        case .hrv: hrv(on: day).map { DayRange([Double($0)])! }
        case .steps: stepsTotal(on: day) > 0 ? DayRange([Double(stepsTotal(on: day))]) : nil
        }
    }

    /// Individual readings of a day; HRV follows the night (D-1 18:00 to D 12:00) like its daily
    /// value. Resting HR has none (it is one value per day).
    public func readings(_ metric: Metric, on day: Date) -> [Reading] {
        switch metric {
        case .heartRate: inside(readings.heartRate, dayInterval(of: day))
        case .hrv: inside(readings.hrv, nightInterval(of: day))
        case .temperature: inside(readings.temperature, nightInterval(of: day))
        case .spo2: inside(readings.spo2, dayInterval(of: day))
        case .steps: stepsByHour(on: day)
        case .restingHeartRate: []
        }
    }

    /// One value per loaded day that has data.
    public func series(_ metric: Metric) -> [DailyValue] {
        days.compactMap { day in value(metric, on: day).map { DailyValue(day: day, range: $0) } }
    }

    public func stepsTotal(on day: Date) -> Int {
        Int(inside(readings.steps, dayInterval(of: day)).reduce(0) { $0 + $1.value })
    }

    public func distanceMeters(on day: Date) -> Int {
        Int(inside(readings.distance, dayInterval(of: day)).reduce(0) { $0 + $1.value })
    }

    /// Steps summed per hour of the day (hours without steps are left out), at the hour start.
    public func stepsByHour(on day: Date) -> [Reading] {
        let hours = Dictionary(grouping: inside(readings.steps, dayInterval(of: day))) {
            calendar.dateInterval(of: .hour, for: $0.date)!.start
        }
        return hours.map { Reading(date: $0.key, value: $0.value.reduce(0) { $0 + $1.value }) }.sorted { $0.date < $1.date }
    }

    /// Workouts that started on `day`, newest first.
    public func workouts(on day: Date) -> [Workout] {
        let interval = dayInterval(of: day)
        return readings.workouts.filter { $0.start >= interval.start && $0.start < interval.end }.reversed()
    }

    /// Workouts in the loaded days, newest first.
    public func workouts() -> [Workout] {
        guard let first = days.first, let last = days.last else { return [] }
        let from = dayInterval(of: first).start, to = dayInterval(of: last).end
        return readings.workouts.filter { $0.start >= from && $0.start < to }.reversed()
    }

    /// Sleep belongs to day D when it ends between D-1 18:00 and D 18:00: contiguous windows, so a
    /// sleep ending in the afternoon (a lie-in, a night shift) still counts.
    public func sleepWindow(of day: Date) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let previous = calendar.date(byAdding: .day, value: -1, to: start)!
        return DateInterval(start: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previous)!,
                            end: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start)!)
    }

    /// The main sleep of day D (ending between D-1 18:00 and D 18:00).
    public func sleep(on day: Date) -> SleepNight? {
        let start = calendar.startOfDay(for: day)
        if let cached = nights[start] { return cached }
        return SleepAnalysis.night(in: sleepWindow(of: day), sessions: sleepSessions)
    }

    /// Up to this many previous nights feed the regularity contributor.
    public static let regularityNights = 14

    /// The night's score, with the previous nights' midpoints for regularity.
    public func sleepScore(on day: Date) -> SleepScore? {
        guard let night = sleep(on: day) else { return nil }
        let previous = (1...Self.regularityNights).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: day).flatMap { sleep(on: $0)?.midpoint }
        }
        return SleepScore(night: night, calendar: calendar, recentMidpoints: previous)
    }

    /// One entry per loaded day that has a night.
    public func sleepSeries() -> [NightValue] {
        days.compactMap { day in
            guard let night = sleep(on: day), let score = sleepScore(on: day) else { return nil }
            return NightValue(day: day, night: night, score: score)
        }
    }

    /// The lowest heart-rate reading while asleep in the night's main sleep (naps don't count).
    public func lowestHeartRate(on day: Date) -> Reading? {
        guard let night = sleep(on: day) else { return nil }
        return readings(.heartRate, during: night).filter { readings.isAsleep(at: $0.date) }.min { $0.value < $1.value }
    }

    /// Heart-rate or HRV readings during a night's session.
    public func readings(_ metric: Metric, during night: SleepNight) -> [Reading] {
        let interval = DateInterval(start: night.inBedStart, end: night.inBedEnd)
        switch metric {
        case .heartRate, .restingHeartRate: return inside(readings.heartRate, interval)
        case .hrv: return inside(readings.hrv, interval)
        case .spo2: return inside(readings.spo2, interval)
        case .temperature: return inside(readings.temperature, interval)
        case .steps: return inside(readings.steps, interval)
        }
    }

    private func asleepReadings(_ list: [Reading], night day: Date) -> [Reading] {
        inside(list, nightInterval(of: day)).filter { readings.isAsleep(at: $0.date) }
    }

    /// Half-open: a reading exactly at the end belongs to the next interval.
    /// Readings lists are sorted by date (see `Readings`), so a binary search finds the slice.
    private func inside(_ list: [Reading], _ interval: DateInterval) -> [Reading] {
        Array(list[Self.firstIndex(in: list, notBefore: interval.start)..<Self.firstIndex(in: list, notBefore: interval.end)])
    }

    private static func firstIndex(in list: [Reading], notBefore date: Date) -> Int {
        var low = 0, high = list.count
        while low < high {
            let mid = (low + high) / 2
            if list[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
