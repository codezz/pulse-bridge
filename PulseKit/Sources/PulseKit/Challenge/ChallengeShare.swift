import Foundation

/// Today's numbers for the share text; the app turns them into a message in its language.
public struct ChallengeShareSummary: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let name: String
        public let total: Int
        public let target: Int
        public var done: Bool { target > 0 && total >= target }

        public init(name: String, total: Int, target: Int) {
            self.name = name
            self.total = total
            self.target = target
        }
    }

    public let day: Date
    public let items: [Item]
    public let streak: Int
    public let daysDone: Int
    public let challengeDay: Int
}

extension ChallengeHistory {
    /// The exercises active today in the user's order, the streak, days done and the day number.
    public func shareSummary(today: Date) -> ChallengeShareSummary {
        let items = exercises.filter { isActive($0, on: today) }.map { exercise in
            let progress = progress(of: exercise, on: today)
            return ChallengeShareSummary.Item(name: exercise.name, total: progress.total, target: progress.target)
        }
        return ChallengeShareSummary(day: today, items: items, streak: streak(today: today),
                                     daysDone: daysDone(today: today), challengeDay: challengeDay(today: today))
    }
}

extension ChallengeShareSummary {
    /// The message for the group chat, in the app's language (or `language`):
    ///
    ///     💪 Ziua 37/42. 5 zile la rând
    ///     ✅ 60F/60G
    ///
    /// ✅ when every exercise reached its target, ⏳ otherwise; each count carries the first letter of
    /// the exercise's name (the default exercises' name in `language`). Without a streak, the first
    /// line is the day alone.
    public func text(language: String? = nil) -> String {
        let first = streak > 0
            ? L("💪 Day \(daysDone)/\(challengeDay). \(streak)-day streak", language: language)
            : L("💪 Day \(daysDone)/\(challengeDay)", language: language)
        let counts = items.map { "\($0.total)\(ChallengeDefaults.name($0.name, in: language).first.map { String($0).uppercased() } ?? "")" }
        let mark = !items.isEmpty && items.allSatisfy(\.done) ? "✅" : "⏳"
        return "\(first)\n\(mark) \(counts.joined(separator: "/"))"
    }
}
