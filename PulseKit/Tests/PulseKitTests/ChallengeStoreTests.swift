import Foundation
import Testing
@testable import PulseKit

@MainActor
struct ChallengeStoreTests {
    let store: ChallengeStore
    let t0 = utcDate(2026, 10, 5, 9, 0)

    init() throws {
        store = ChallengeStore(container: try RecordStore.container(inMemory: true))
    }

    @Test func addLogAndUndo() throws {
        let id = try store.addExercise(name: "Push-ups", unit: .reps, target: 60, at: t0)
        try store.log(20, exerciseID: id, at: t0 + 60)
        try store.log(10, exerciseID: id, at: t0 + 120)
        #expect(try store.sets().map(\.count) == [20, 10])
        #expect(try store.undoLast(exerciseID: id, on: t0))
        #expect(try store.sets().map(\.count) == [20])
        #expect(try store.exercises().map(\.name) == ["Push-ups"])
    }

    /// A typo like 100000000 must not end up in the totals.
    @Test func implausibleCountsAreRejected() throws {
        let id = try store.addExercise(name: "Push-ups", unit: .reps, target: 60, at: t0)
        try store.log(10_001, exerciseID: id, at: t0)
        try store.log(0, exerciseID: id, at: t0)
        try store.log(10_000, exerciseID: id, at: t0)
        #expect(try store.sets().map(\.count) == [10_000])
    }

    /// The app was killed mid-session: close it at its last set so the workout still reaches Health.
    @Test func openSessionsAreClosedAtTheirLastSet() throws {
        let id = try store.addExercise(name: "Push-ups", unit: .reps, target: 60, at: t0)
        let kept = try store.startSession(at: t0)
        try store.log(20, exerciseID: id, at: t0 + 300, sessionID: kept)
        let empty = try store.startSession(at: t0 + 1000)
        #expect(try store.closeOpenSessions() == 1)
        let pending = try store.pendingSessions()
        #expect(pending.map(\.id) == [kept])
        #expect(pending.first?.end == t0 + 300)
        _ = empty
    }

    @Test func sameDayEditReplaces() throws {
        let id = try store.addExercise(name: "Squats", unit: .reps, target: 60, at: t0)
        try store.setTarget(id, target: 65, autoStep: 0, autoWeekday: nil, at: t0 + 3600)
        try store.setTarget(id, target: 70, autoStep: 5, autoWeekday: 2, at: t0 + 7200)
        try store.setTarget(id, target: 80, autoStep: 0, autoWeekday: nil, at: t0 + 86400)
        let changes = try #require(try store.exercises().first).changes
        #expect(changes.map(\.target) == [70, 80])
        #expect(changes.first?.autoStep == 5)
    }

    @Test func archiveHidesButKeeps() throws {
        let a = try store.addExercise(name: "A", unit: .reps, target: 10, at: t0)
        _ = try store.addExercise(name: "B", unit: .seconds, target: 30, at: t0)
        try store.archive(a, at: t0 + 60)
        #expect(try store.exercises().map(\.name) == ["B"])
        #expect(try store.exercises(includeArchived: true).count == 2)
    }

    @Test func sessionCollectsItsSets() throws {
        let id = try store.addExercise(name: "Push-ups", unit: .reps, target: 60, at: t0)
        let session = try store.startSession(at: t0)
        try store.log(20, exerciseID: id, at: t0 + 60, sessionID: session)
        try store.log(5, exerciseID: id, at: t0 + 90)
        try store.finishSession(session, at: t0 + 600, heart: [HeartSample(date: t0 + 30, bpm: 110)])
        let pending = try store.pendingSessions()
        #expect(pending.map(\.id) == [session])
        #expect(pending.first?.reps.map(\.count) == [20])
        #expect(pending.first?.heart.count == 1)
        try store.markSessionExported(session)
        #expect(try store.pendingSessions().isEmpty)
    }
}
