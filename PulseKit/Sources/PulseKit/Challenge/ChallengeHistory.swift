import Foundation

public enum ExerciseUnit: String, Codable, Sendable, CaseIterable {
    case reps, seconds
}

/// A target set on `day`, growing by `autoStep` on every `autoWeekday` (Calendar weekday, 1 = Sunday)
/// after that day. Later changes take over from their own day; earlier days keep their target.
public struct TargetChange: Sendable, Equatable {
    public let day: Date
    public let target: Int
    public let autoStep: Int
    public let autoWeekday: Int?

    public init(day: Date, target: Int, autoStep: Int = 0, autoWeekday: Int? = nil) {
        self.day = day
        self.target = target
        self.autoStep = autoStep
        self.autoWeekday = autoWeekday
    }
}

public struct ExerciseInfo: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let unit: ExerciseUnit
    public let createdAt: Date
    public let archivedAt: Date?
    /// Oldest first.
    public let changes: [TargetChange]

    public init(id: UUID, name: String, unit: ExerciseUnit, createdAt: Date, archivedAt: Date?, changes: [TargetChange]) {
        self.id = id
        self.name = name
        self.unit = unit
        self.createdAt = createdAt
        self.archivedAt = archivedAt
        self.changes = changes
    }

    public var latestChange: TargetChange? { changes.last }
}

public struct SetInfo: Sendable, Equatable {
    public let exerciseID: UUID
    public let date: Date
    public let count: Int

    public init(exerciseID: UUID, date: Date, count: Int) {
        self.exerciseID = exerciseID
        self.date = date
        self.count = count
    }
}

public enum DayStatus: Sendable, Equatable {
    case none, partial, done
}

/// Progress from before the app, entered once: when the challenge started and the numbers up to the
/// day before tracking began. Past days aren't invented; the counts just carry over.
public struct ChallengeBaseline: Codable, Sendable, Equatable {
    public var startDate: Date
    public var daysDoneBefore: Int
    public var streakBefore: Int
    public var bestBefore: Int

    public init(startDate: Date, daysDoneBefore: Int, streakBefore: Int, bestBefore: Int) {
        self.startDate = startDate
        self.daysDoneBefore = daysDoneBefore
        self.streakBefore = streakBefore
        self.bestBefore = bestBefore
    }
}

/// One exercise on one day: what was done against what was asked.
public struct ChallengeProgress: Sendable, Equatable {
    public let total: Int
    public let target: Int

    public init(total: Int, target: Int) {
        self.total = total
        self.target = target
    }

    public var isDone: Bool { target > 0 && total >= target }
    /// 0...1 and beyond, for rings and bars.
    public var fraction: Double { target > 0 ? Double(total) / Double(target) : 0 }
}

/// The challenge's rules over stored values: targets per day, day status, streaks, totals.
public struct ChallengeHistory: Sendable {
    public let exercises: [ExerciseInfo]
    public let sets: [SetInfo]
    public let baseline: ChallengeBaseline?
    private let calendar: Calendar
    private let dayTotals: [UUID: [Date: Int]]

    public init(exercises: [ExerciseInfo], sets: [SetInfo], calendar: Calendar, baseline: ChallengeBaseline? = nil) {
        self.exercises = exercises
        self.sets = sets
        self.calendar = calendar
        self.baseline = baseline
        var totals: [UUID: [Date: Int]] = [:]
        for set in sets { totals[set.exerciseID, default: [:]][calendar.startOfDay(for: set.date), default: 0] += set.count }
        dayTotals = totals
    }

    public func target(of exercise: ExerciseInfo, on day: Date) -> Int? {
        let start = calendar.startOfDay(for: day)
        guard let change = exercise.changes.last(where: { calendar.startOfDay(for: $0.day) <= start }) else { return nil }
        guard change.autoStep != 0, let weekday = change.autoWeekday else { return change.target }
        let from = calendar.startOfDay(for: change.day)
        return max(0, change.target + change.autoStep * occurrences(of: weekday, after: from, through: start))
    }

    /// How many `weekday` dates fall in `(from, through]`, without walking the days (this runs for
    /// every day of every streak).
    private func occurrences(of weekday: Int, after from: Date, through: Date) -> Int {
        let days = calendar.dateComponents([.day], from: from, to: through).day ?? 0
        guard days > 0 else { return 0 }
        let first = (weekday - calendar.component(.weekday, from: from) + 7) % 7
        let firstOffset = first == 0 ? 7 : first
        return firstOffset > days ? 0 : (days - firstOffset) / 7 + 1
    }

    public func total(of exerciseID: UUID, on day: Date) -> Int {
        dayTotals[exerciseID]?[calendar.startOfDay(for: day)] ?? 0
    }

    public func progress(of exercise: ExerciseInfo, on day: Date) -> ChallengeProgress {
        ChallengeProgress(total: total(of: exercise.id, on: day), target: target(of: exercise, on: day) ?? 0)
    }

    /// The Monday-to-Monday week containing `day`, whatever the locale's first weekday.
    public func week(containing day: Date) -> DateInterval {
        var monday = calendar
        monday.firstWeekday = 2
        return monday.dateInterval(of: .weekOfYear, for: day)!
    }

    public func isActive(_ exercise: ExerciseInfo, on day: Date) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard calendar.startOfDay(for: exercise.createdAt) <= start else { return false }
        return exercise.archivedAt.map { start < calendar.startOfDay(for: $0) } ?? true
    }

    public func status(on day: Date) -> DayStatus {
        let goals = exercises.compactMap { e -> (UUID, Int)? in
            guard isActive(e, on: day), let target = target(of: e, on: day) else { return nil }
            return (e.id, target)
        }
        guard !goals.isEmpty else { return .none }
        if goals.allSatisfy({ total(of: $0.0, on: day) >= $0.1 }) { return .done }
        return exercises.contains { total(of: $0.id, on: day) > 0 } ? .partial : .none
    }

    /// Done days in a row, ending today if today is done, otherwise yesterday. A run reaching back to
    /// the first tracked day continues the streak from before the app.
    public func streak(today: Date) -> Int {
        var day = calendar.startOfDay(for: today)
        if status(on: day) != .done { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while day >= earliest, status(on: day) == .done {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        if day < earliest { count += baseline?.streakBefore ?? 0 }
        return count
    }

    public func bestStreak(today: Date) -> Int {
        var run = baseline?.streakBefore ?? 0
        var best = max(baseline?.bestBefore ?? 0, run)
        var day = earliest
        let end = calendar.startOfDay(for: today)
        while day <= end {
            run = status(on: day) == .done ? run + 1 : 0
            best = max(best, run)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return best
    }

    /// Days completed, including the ones from before the app.
    public func daysDone(today: Date) -> Int {
        var count = baseline?.daysDoneBefore ?? 0
        var day = earliest
        let end = calendar.startOfDay(for: today)
        while day <= end {
            if status(on: day) == .done { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    /// Day number of the challenge today (1 on its first day).
    public func challengeDay(today: Date) -> Int {
        let start = calendar.startOfDay(for: baseline?.startDate ?? earliest)
        return (calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: today)).day ?? 0) + 1
    }

    /// Between the challenge's start and the first day tracked in the app: known only as totals.
    public func isBeforeTracking(_ day: Date) -> Bool {
        guard let baseline else { return false }
        let start = calendar.startOfDay(for: day)
        return start >= calendar.startOfDay(for: baseline.startDate) && start < earliest
    }

    /// The first day tracked in the app.
    public var firstTrackedDay: Date { earliest }

    /// Sum of an exercise's sets in `[start, end)`.
    public func total(of exerciseID: UUID, in interval: DateInterval) -> Int {
        sets.filter { $0.exerciseID == exerciseID && $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.count }
    }

    public func sets(on day: Date) -> [SetInfo] {
        let start = calendar.startOfDay(for: day)
        return sets.filter { calendar.startOfDay(for: $0.date) == start }.sorted { $0.date < $1.date }
    }

    private var earliest: Date {
        calendar.startOfDay(for: exercises.map(\.createdAt).min() ?? .distantFuture)
    }
}
