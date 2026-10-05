import Foundation

public struct ReadinessContributor: Sendable, Equatable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case hrv, restingHeartRate, sleep, activity
    }

    public let kind: Kind
    /// 0-100.
    public let score: Int
    /// e.g. "48 ms · usual 42"
    public let detail: String
    public var id: Kind { kind }
}

public struct ReadinessScore: Sendable, Equatable {
    public let value: Int
    public let contributors: [ReadinessContributor]
    public let reason: String
    public var label: String { SleepScore.label(for: value) }
}

public enum ReadinessResult: Sendable, Equatable {
    case score(ReadinessScore)
    /// Not enough nights for a baseline yet (or no reading last night).
    case calibrating(nightsNeeded: Int)
}

/// Morning readiness from last night against the user's own baseline (see the design spec).
public enum Readiness {
    static let weights: [ReadinessContributor.Kind: Double] = [.hrv: 0.4, .restingHeartRate: 0.3, .sleep: 0.2, .activity: 0.1]
    static let baselineNights = 5
    static let baselineDays = 30

    public static func compute(_ series: [InsightTopic: [Date: Double]], sleepScore: Int?, today: Date, calendar: Calendar) -> ReadinessResult {
        let day = calendar.startOfDay(for: today)
        let hrv = lastAndBaseline(series[.hrv], day, calendar)
        let resting = lastAndBaseline(series[.restingHeartRate], day, calendar)
        var contributors: [ReadinessContributor] = []
        if let (last, usual) = hrv.values {
            contributors.append(ReadinessContributor(kind: .hrv, score: scale(last / usual, zeroAt: 0.75, fullAt: 1.05),
                                                     detail: "\(Int(last.rounded())) ms · usual \(Int(usual.rounded()))"))
        }
        if let (last, usual) = resting.values {
            contributors.append(ReadinessContributor(kind: .restingHeartRate, score: scale(last - usual, zeroAt: 8, fullAt: -1),
                                                     detail: "\(Int(last.rounded())) bpm · usual \(Int(usual.rounded()))"))
        }
        guard !contributors.isEmpty else {
            return .calibrating(nightsNeeded: max(0, baselineNights - max(hrv.earlier, resting.earlier)))
        }
        if let sleepScore {
            contributors.append(ReadinessContributor(kind: .sleep, score: min(100, max(0, sleepScore)), detail: "Sleep score \(sleepScore)"))
        }
        if let activity = activityBalance(series[.steps], day, calendar) { contributors.append(activity) }

        let total = contributors.reduce(0) { $0 + weights[$1.kind]! }
        let value = contributors.reduce(0) { $0 + Double($1.score) * weights[$1.kind]! } / total
        let score = Int(value.rounded())
        return .score(ReadinessScore(value: score, contributors: contributors,
                                     reason: reason(contributors, score, hrv: hrv.values, resting: resting.values)))
    }

    // MARK: Contributors

    /// Last night's value and the average of up to 30 earlier nights (needs 5).
    private static func lastAndBaseline(_ series: [Date: Double]?, _ day: Date, _ calendar: Calendar) -> (values: (Double, Double)?, earlier: Int) {
        guard let series else { return (nil, 0) }
        let from = calendar.date(byAdding: .day, value: -baselineDays, to: day)!
        let earlier = series.filter { $0.key < day && $0.key >= from }.map(\.value)
        guard let last = series[day], earlier.count >= baselineNights else { return (nil, earlier.count) }
        return ((last, earlier.reduce(0, +) / Double(earlier.count)), earlier.count)
    }

    /// Yesterday's steps against the 14 days before it: a big day lowers readiness a little.
    private static func activityBalance(_ series: [Date: Double]?, _ day: Date, _ calendar: Calendar) -> ReadinessContributor? {
        guard let series else { return nil }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day)!
        let before = (2...15).compactMap { series[calendar.date(byAdding: .day, value: -$0, to: day)!] }
        guard let steps = series[yesterday], before.count >= 4 else { return nil }
        let usual = before.reduce(0, +) / Double(before.count)
        guard usual > 0 else { return nil }
        let ratio = steps / usual
        let score = ratio <= 1.3 ? 100 : max(40, Int((100 - (ratio - 1.3) / 1.2 * 60).rounded()))
        return ReadinessContributor(kind: .activity, score: score,
                                    detail: "\(Int(steps.rounded()).formatted()) steps · usual \(Int(usual.rounded()).formatted())")
    }

    /// 0 at `zeroAt`, 100 at `fullAt`, linear between, clamped (works in either direction).
    private static func scale(_ value: Double, zeroAt: Double, fullAt: Double) -> Int {
        let fraction = (value - zeroAt) / (fullAt - zeroAt)
        return Int((min(1, max(0, fraction)) * 100).rounded())
    }

    private static func reason(_ contributors: [ReadinessContributor], _ score: Int,
                               hrv: (Double, Double)?, resting: (Double, Double)?) -> String {
        guard let weakest = contributors.min(by: { $0.score < $1.score }), weakest.score < 70 else {
            return score >= 85 ? "You're recovered" : "Steady"
        }
        switch weakest.kind {
        case .hrv:
            let percent = hrv.map { Int(((1 - $0.0 / $0.1) * 100).rounded()) } ?? 0
            return "HRV \(percent)% below your usual"
        case .restingHeartRate:
            let above = resting.map { Int(($0.0 - $0.1).rounded()) } ?? 0
            return "Resting heart rate \(above) above your usual"
        case .sleep: return "Short or restless sleep"
        case .activity: return "Big activity day yesterday"
        }
    }
}
