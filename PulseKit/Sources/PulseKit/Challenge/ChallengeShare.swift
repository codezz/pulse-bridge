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
