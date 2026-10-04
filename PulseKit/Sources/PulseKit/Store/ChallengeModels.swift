import Foundation
import SwiftData

@Model
public final class ChallengeExercise {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var unitRaw: String
    public var order: Int
    public var createdAt: Date
    public var archivedAt: Date?

    init(id: UUID, name: String, unit: ExerciseUnit, order: Int, createdAt: Date) {
        self.id = id
        self.name = name
        unitRaw = unit.rawValue
        self.order = order
        self.createdAt = createdAt
    }
}

@Model
public final class ChallengeTargetChange {
    public var exerciseID: UUID
    public var day: Date
    public var target: Int
    public var autoStep: Int
    public var autoWeekday: Int?

    init(exerciseID: UUID, day: Date, target: Int, autoStep: Int, autoWeekday: Int?) {
        self.exerciseID = exerciseID
        self.day = day
        self.target = target
        self.autoStep = autoStep
        self.autoWeekday = autoWeekday
    }
}

@Model
public final class ChallengeSet {
    @Attribute(.unique) public var id: UUID
    public var exerciseID: UUID
    public var date: Date
    public var count: Int
    public var sessionID: UUID?

    init(exerciseID: UUID, date: Date, count: Int, sessionID: UUID?) {
        id = UUID()
        self.exerciseID = exerciseID
        self.date = date
        self.count = count
        self.sessionID = sessionID
    }
}

@Model
public final class ChallengeSession {
    @Attribute(.unique) public var id: UUID
    public var start: Date
    public var end: Date?
    /// `[HeartSample]` as JSON.
    public var heart: Data
    public var exported: Bool

    init(id: UUID, start: Date) {
        self.id = id
        self.start = start
        heart = Data()
        exported = false
    }
}

public struct SessionInfo: Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let heart: [HeartSample]
    public let reps: [(name: String, count: Int)]
}
