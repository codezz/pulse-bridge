import Foundation

public enum InsightTopic: String, CaseIterable, Sendable {
    case sleep, steps, restingHeartRate, hrv, heartRate, spo2, temperature
}

public enum InsightDirection: Sendable, Equatable {
    case better, worse, neutral
}

/// One line about a change worth noticing, e.g. "Resting heart rate 56 bpm, 3 below your recent average".
public struct Insight: Sendable, Equatable, Identifiable {
    public let topic: InsightTopic
    public let text: String
    public let direction: InsightDirection
    public var id: String { topic.rawValue }

    public init(topic: InsightTopic, text: String, direction: InsightDirection) {
        self.topic = topic
        self.text = text
        self.direction = direction
    }
}

/// The last 7 days against the 7 before.
public struct WeekComparison: Sendable, Equatable {
    public let this: Double
    public let last: Double
    public var change: Double { this - last }

    public init(this: Double, last: Double) {
        self.this = this
        self.last = last
    }
}

/// Highlights from per-day values. Only speaks when there's enough data and the change is real.
public enum Insights {
    static let minimumNights = 5
    static let minimumWeekDays = 4

    public static func make(_ series: [InsightTopic: [Date: Double]], today: Date, calendar: Calendar) -> [Insight] {
        [restingHeartRate(series[.restingHeartRate], today, calendar),
         sleep(series[.sleep], today, calendar),
         hrv(series[.hrv], today, calendar),
         steps(series[.steps], today, calendar),
         temperature(series[.temperature], today, calendar)].compactMap { $0 }
    }

    /// Average of the last 7 days against the 7 before; `endingYesterday` for totals still growing today.
    public static func week(_ series: [Date: Double], today: Date, calendar: Calendar, endingYesterday: Bool = false) -> WeekComparison? {
        let end = endingYesterday ? calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today))! : calendar.startOfDay(for: today)
        let this = values(series, endingOn: end, days: 7, calendar)
        let last = values(series, endingOn: calendar.date(byAdding: .day, value: -7, to: end)!, days: 7, calendar)
        guard this.count >= minimumWeekDays, last.count >= minimumWeekDays else { return nil }
        return WeekComparison(this: average(this), last: average(last))
    }

    /// Arrow for a week-over-week change, with the same thresholds as the highlights (smaller is
    /// neutral). Lower is better only for heart rate.
    public static func direction(_ topic: InsightTopic, _ comparison: WeekComparison) -> InsightDirection {
        let change = comparison.change
        let meaningful: Bool
        switch topic {
        case .sleep: meaningful = abs(change) >= 15
        case .restingHeartRate, .heartRate: meaningful = abs(change) >= 2
        case .spo2: meaningful = abs(change) >= 1
        case .temperature: meaningful = abs(change) >= 0.3
        case .steps, .hrv: meaningful = comparison.last > 0 && abs(change / comparison.last) >= 0.10
        }
        guard meaningful else { return .neutral }
        switch topic {
        case .restingHeartRate, .heartRate: return change < 0 ? .better : .worse
        case .temperature: return change > 0 ? .worse : .neutral
        case .sleep, .steps, .hrv, .spo2: return change > 0 ? .better : .worse
        }
    }

    // MARK: Rules

    private static func restingHeartRate(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar) else { return nil }
        let diff = Int(last.rounded()) - Int(usual.rounded())
        guard abs(diff) >= 2 else { return nil }
        return Insight(topic: .restingHeartRate,
                       text: "Resting heart rate \(Int(last.rounded())) bpm, \(abs(diff)) \(diff < 0 ? "below" : "above") your recent average",
                       direction: diff < 0 ? .better : .worse)
    }

    private static func hrv(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar), usual > 0 else { return nil }
        let percent = Int(((last - usual) / usual * 100).rounded())
        guard abs(percent) >= 10 else { return nil }
        return Insight(topic: .hrv, text: "HRV \(Int(last.rounded())) ms, \(abs(percent))% \(percent > 0 ? "higher" : "lower") than usual",
                       direction: percent > 0 ? .better : .worse)
    }

    /// A warmer night than usual is an early sign of illness, overtraining or a heavy evening.
    private static func temperature(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar) else { return nil }
        let diff = ((last - usual) * 10).rounded() / 10
        guard abs(diff) >= 0.3 else { return nil }
        return Insight(topic: .temperature,
                       text: "Night temperature \(String(format: "%.1f", abs(diff))) °C \(diff > 0 ? "above" : "below") your usual",
                       direction: diff > 0 ? .worse : .neutral)
    }

    private static func sleep(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> Insight? {
        guard let series, let week = week(series, today: today, calendar: calendar) else { return nil }
        let minutes = Int(week.change.rounded())
        guard abs(minutes) >= 15 else { return nil }
        return Insight(topic: .sleep, text: "You slept \(abs(minutes)) min \(minutes > 0 ? "more" : "less") per night than the week before",
                       direction: minutes > 0 ? .better : .worse)
    }

    private static func steps(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> Insight? {
        guard let series, let week = week(series, today: today, calendar: calendar, endingYesterday: true), week.last > 0 else { return nil }
        let percent = Int((week.change / week.last * 100).rounded())
        guard abs(percent) >= 10 else { return nil }
        return Insight(topic: .steps, text: "Steps \(percent > 0 ? "up" : "down") \(abs(percent))% on the week before",
                       direction: percent > 0 ? .better : .worse)
    }

    // MARK: Helpers

    /// Today's value and the average of the earlier days (needs at least 5 of them), for screens
    /// that show "vs your usual".
    public static func usual(_ series: [Date: Double]?, today: Date, calendar: Calendar) -> (last: Double, usual: Double)? {
        lastAgainstUsual(series, today, calendar).map { (last: $0.0, usual: $0.1) }
    }

    /// Today's value and the average of the earlier days (needs at least 5 of them).
    private static func lastAgainstUsual(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> (Double, Double)? {
        guard let series, let last = series[calendar.startOfDay(for: today)] else { return nil }
        let earlier = series.filter { $0.key < calendar.startOfDay(for: today) }.map(\.value)
        guard earlier.count >= minimumNights else { return nil }
        return (last, average(earlier))
    }

    private static func values(_ series: [Date: Double], endingOn end: Date, days: Int, _ calendar: Calendar) -> [Double] {
        (0..<days).compactMap { series[calendar.date(byAdding: .day, value: -$0, to: end)!] }
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}

extension DailyMetrics {
    /// Per-day values for insights and trends, keyed by day start.
    public func insightSeries() -> [InsightTopic: [Date: Double]] {
        var result: [InsightTopic: [Date: Double]] = [:]
        for day in days {
            if let night = sleep(on: day) { result[.sleep, default: [:]][day] = Double(night.asleep) }
            let steps = stepsTotal(on: day)
            if steps > 0 { result[.steps, default: [:]][day] = Double(steps) }
            if let resting = restingHeartRate(on: day) { result[.restingHeartRate, default: [:]][day] = Double(resting) }
            if let hrv = hrv(on: day) { result[.hrv, default: [:]][day] = Double(hrv) }
            if let hr = value(.heartRate, on: day) { result[.heartRate, default: [:]][day] = hr.average }
            if let spo2 = value(.spo2, on: day) { result[.spo2, default: [:]][day] = spo2.average }
            if let temperature = nightTemperature(on: day) { result[.temperature, default: [:]][day] = temperature }
        }
        return result
    }
}
