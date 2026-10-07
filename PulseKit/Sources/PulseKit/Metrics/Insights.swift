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
    /// "Usual" = the average of up to 30 earlier nights (readiness uses the same baseline).
    public static let baselineDays = 30
    static let minimumWeekDays = 4

    public static func make(_ series: [InsightTopic: [Date: Double]], today: Date, calendar: Calendar, language: String? = nil) -> [Insight] {
        [restingHeartRate(series[.restingHeartRate], today, calendar, language),
         sleep(series[.sleep], today, calendar, language),
         hrv(series[.hrv], today, calendar, language),
         steps(series[.steps], today, calendar, language),
         temperature(series[.temperature], today, calendar, language)].compactMap { $0 }
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

    private static func restingHeartRate(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar, _ language: String?) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar) else { return nil }
        let diff = Int(last.rounded()) - Int(usual.rounded())
        guard abs(diff) >= 2 else { return nil }
        let bpm = Int(last.rounded())
        let text = diff < 0
            ? L("Resting heart rate \(bpm) bpm, \(abs(diff)) below your recent average", language: language)
            : L("Resting heart rate \(bpm) bpm, \(abs(diff)) above your recent average", language: language)
        return Insight(topic: .restingHeartRate, text: text, direction: diff < 0 ? .better : .worse)
    }

    private static func hrv(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar, _ language: String?) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar), usual > 0 else { return nil }
        let percent = Int(((last - usual) / usual * 100).rounded())
        guard abs(percent) >= 10 else { return nil }
        let ms = Int(last.rounded())
        let text = percent > 0
            ? L("HRV \(ms) ms, \(abs(percent))% higher than usual", language: language)
            : L("HRV \(ms) ms, \(abs(percent))% lower than usual", language: language)
        return Insight(topic: .hrv, text: text, direction: percent > 0 ? .better : .worse)
    }

    /// A warmer night than usual is an early sign of illness, overtraining or a heavy evening.
    private static func temperature(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar, _ language: String?) -> Insight? {
        guard let (last, usual) = lastAgainstUsual(series, today, calendar) else { return nil }
        let diff = last - usual
        guard abs(diff) >= 0.3 else { return nil }      // the raw difference; rounding is for the text only
        let degrees = abs(diff).formatted(.number.precision(.fractionLength(1)))
        let text = diff > 0
            ? L("Night temperature \(degrees) °C above your usual", language: language)
            : L("Night temperature \(degrees) °C below your usual", language: language)
        return Insight(topic: .temperature, text: text, direction: diff > 0 ? .worse : .neutral)
    }

    /// "+0.3", "-0.3", or "0.0" (never "-0.0") in the locale's decimal style.
    public static func signedCelsius(_ difference: Double, locale: Locale = .current) -> String {
        let rounded = (difference * 10).rounded() / 10
        let text = abs(rounded).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return rounded > 0 ? "+" + text : rounded < 0 ? "-" + text : text
    }

    private static func sleep(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar, _ language: String?) -> Insight? {
        guard let series, let week = week(series, today: today, calendar: calendar) else { return nil }
        let minutes = Int(week.change.rounded())
        guard abs(minutes) >= 15 else { return nil }
        let text = minutes > 0
            ? L("You slept \(abs(minutes)) min more per night than the week before", language: language)
            : L("You slept \(abs(minutes)) min less per night than the week before", language: language)
        return Insight(topic: .sleep, text: text, direction: minutes > 0 ? .better : .worse)
    }

    private static func steps(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar, _ language: String?) -> Insight? {
        guard let series, let week = week(series, today: today, calendar: calendar, endingYesterday: true), week.last > 0 else { return nil }
        let percent = Int((week.change / week.last * 100).rounded())
        guard abs(percent) >= 10 else { return nil }
        let text = percent > 0
            ? L("Steps up \(abs(percent))% on the week before", language: language)
            : L("Steps down \(abs(percent))% on the week before", language: language)
        return Insight(topic: .steps, text: text, direction: percent > 0 ? .better : .worse)
    }

    // MARK: Helpers

    /// Today's value and the average of the earlier days (needs at least 5 of them), for screens
    /// that show "vs your usual".
    public static func usual(_ series: [Date: Double]?, today: Date, calendar: Calendar) -> (last: Double, usual: Double)? {
        lastAgainstUsual(series, today, calendar).map { (last: $0.0, usual: $0.1) }
    }

    /// Today's value and the average of up to 30 earlier nights (needs at least 5).
    private static func lastAgainstUsual(_ series: [Date: Double]?, _ today: Date, _ calendar: Calendar) -> (Double, Double)? {
        let baseline = baseline(series, today: today, calendar: calendar)
        guard let last = baseline.last, let usual = baseline.usual else { return nil }
        return (last, usual)
    }

    /// Last night's value (if any), the usual of the earlier nights in the 30-day window (with at
    /// least 5 of them), and how many earlier nights there are. Shared with readiness.
    public static func baseline(_ series: [Date: Double]?, today: Date, calendar: Calendar)
        -> (last: Double?, usual: Double?, earlier: Int) {
        guard let series else { return (nil, nil, 0) }
        let day = calendar.startOfDay(for: today)
        let from = calendar.date(byAdding: .day, value: -baselineDays, to: day)!
        let earlier = series.filter { $0.key < day && $0.key >= from }.map(\.value)
        return (series[day], earlier.count >= minimumNights ? average(earlier) : nil, earlier.count)
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
            // Night values only (no daytime fallback), so baselines compare nights with nights.
            if let resting = restingHeartRate(on: day, asleepOnly: true) { result[.restingHeartRate, default: [:]][day] = Double(resting) }
            if let hrv = hrv(on: day, asleepOnly: true) { result[.hrv, default: [:]][day] = Double(hrv) }
            if let hr = value(.heartRate, on: day) { result[.heartRate, default: [:]][day] = hr.average }
            if let spo2 = value(.spo2, on: day) { result[.spo2, default: [:]][day] = spo2.average }
            if let temperature = nightTemperature(on: day, asleepOnly: true) { result[.temperature, default: [:]][day] = temperature }
        }
        return result
    }
}
