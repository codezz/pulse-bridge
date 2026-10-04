import Foundation
import SwiftData

/// The challenge's data on the phone: exercises, dated target changes, logged sets, timed sessions.
@MainActor
public final class ChallengeStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let calendar: Calendar

    public init(container: ModelContainer, calendar: Calendar = .current) {
        self.container = container
        self.calendar = calendar
    }

    public func exercises(includeArchived: Bool = false) throws -> [ExerciseInfo] {
        let changes = try context.fetch(FetchDescriptor<ChallengeTargetChange>(sortBy: [SortDescriptor(\.day)]))
        return try context.fetch(FetchDescriptor<ChallengeExercise>(sortBy: [SortDescriptor(\.order)]))
            .filter { includeArchived || $0.archivedAt == nil }
            .map { e in
                ExerciseInfo(id: e.id, name: e.name, unit: ExerciseUnit(rawValue: e.unitRaw) ?? .reps, createdAt: e.createdAt,
                             archivedAt: e.archivedAt,
                             changes: changes.filter { $0.exerciseID == e.id }
                                 .map { TargetChange(day: $0.day, target: $0.target, autoStep: $0.autoStep, autoWeekday: $0.autoWeekday) })
            }
    }

    @discardableResult
    public func addExercise(name: String, unit: ExerciseUnit, target: Int, autoStep: Int = 0, autoWeekday: Int? = nil,
                            at date: Date) throws -> UUID {
        let id = UUID()
        let order = (try context.fetch(FetchDescriptor<ChallengeExercise>()).map(\.order).max() ?? -1) + 1
        context.insert(ChallengeExercise(id: id, name: name, unit: unit, order: order, createdAt: date))
        try setTarget(id, target: target, autoStep: autoStep, autoWeekday: autoWeekday, at: date)
        return id
    }

    /// A change dated today; another edit the same day replaces it.
    public func setTarget(_ exerciseID: UUID, target: Int, autoStep: Int, autoWeekday: Int?, at date: Date) throws {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        try context.delete(model: ChallengeTargetChange.self,
                           where: #Predicate { $0.exerciseID == exerciseID && $0.day >= day && $0.day < next })
        context.insert(ChallengeTargetChange(exerciseID: exerciseID, day: day, target: target, autoStep: autoStep, autoWeekday: autoWeekday))
        try context.save()
    }

    public func rename(_ exerciseID: UUID, to name: String) throws {
        try exercise(exerciseID)?.name = name
        try context.save()
    }

    public func archive(_ exerciseID: UUID, at date: Date) throws {
        try exercise(exerciseID)?.archivedAt = date
        try context.save()
    }

    /// New order of the given exercise ids.
    public func reorder(_ ids: [UUID]) throws {
        for (index, id) in ids.enumerated() { try exercise(id)?.order = index }
        try context.save()
    }

    public func log(_ count: Int, exerciseID: UUID, at date: Date, sessionID: UUID? = nil) throws {
        guard count > 0 else { return }
        context.insert(ChallengeSet(exerciseID: exerciseID, date: date, count: count, sessionID: sessionID))
        try context.save()
    }

    /// Removes the exercise's latest set on that day; false if there was none.
    public func undoLast(exerciseID: UUID, on day: Date) throws -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        var descriptor = FetchDescriptor<ChallengeSet>(
            predicate: #Predicate { $0.exerciseID == exerciseID && $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = try context.fetch(descriptor).first else { return false }
        context.delete(last)
        try context.save()
        return true
    }

    public func sets() throws -> [SetInfo] {
        try context.fetch(FetchDescriptor<ChallengeSet>(sortBy: [SortDescriptor(\.date)]))
            .map { SetInfo(exerciseID: $0.exerciseID, date: $0.date, count: $0.count) }
    }

    public func startSession(at date: Date) throws -> UUID {
        let id = UUID()
        context.insert(ChallengeSession(id: id, start: date))
        try context.save()
        return id
    }

    public func finishSession(_ id: UUID, at date: Date, heart: [HeartSample]) throws {
        guard let session = try session(id) else { return }
        session.end = date
        session.heart = (try? JSONEncoder().encode(heart)) ?? Data()
        try context.save()
    }

    /// Drops the timing; the sets stay as ordinary sets.
    public func cancelSession(_ id: UUID) throws {
        for set in try context.fetch(FetchDescriptor<ChallengeSet>(predicate: #Predicate { $0.sessionID == id })) { set.sessionID = nil }
        if let session = try session(id) { context.delete(session) }
        try context.save()
    }

    /// Finished sessions not yet in Health, with their reps per exercise.
    public func pendingSessions() throws -> [SessionInfo] {
        let names = Dictionary(uniqueKeysWithValues: try exercises(includeArchived: true).map { ($0.id, $0.name) })
        return try context.fetch(FetchDescriptor<ChallengeSession>(predicate: #Predicate { $0.exported == false && $0.end != nil },
                                                                 sortBy: [SortDescriptor(\.start)]))
            .compactMap { session in
                guard let end = session.end else { return nil }
                let id = session.id
                let sets = try context.fetch(FetchDescriptor<ChallengeSet>(predicate: #Predicate { $0.sessionID == id }))
                var reps: [UUID: Int] = [:]
                for set in sets { reps[set.exerciseID, default: 0] += set.count }
                return SessionInfo(id: id, start: session.start, end: end,
                                   heart: (try? JSONDecoder().decode([HeartSample].self, from: session.heart)) ?? [],
                                   reps: reps.map { (names[$0.key] ?? "?", $0.value) }.sorted { $0.name < $1.name })
            }
    }

    public func markSessionExported(_ id: UUID) throws {
        try session(id)?.exported = true
        try context.save()
    }

    private func exercise(_ id: UUID) throws -> ChallengeExercise? {
        try context.fetch(FetchDescriptor<ChallengeExercise>(predicate: #Predicate { $0.id == id })).first
    }

    private func session(_ id: UUID) throws -> ChallengeSession? {
        try context.fetch(FetchDescriptor<ChallengeSession>(predicate: #Predicate { $0.id == id })).first
    }
}
