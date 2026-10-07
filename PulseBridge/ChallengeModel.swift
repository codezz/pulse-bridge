import Foundation
import Observation
import PulseKit

/// The challenge as the views see it. Owned by SyncCoordinator so the heart-rate stream and Health
/// retries live in one place.
@MainActor
@Observable
final class ChallengeModel {
    private let store: ChallengeStore
    @ObservationIgnored private let exporter = ChallengeExporter()
    @ObservationIgnored private var isExporting = false
    @ObservationIgnored var onSessionChange: (() -> Void)?
    /// Writes a line to the diagnostics log.
    @ObservationIgnored var note: ((String) -> Void)?
    @ObservationIgnored private var exportAgain = false

    private(set) var exercises: [ExerciseInfo] = []
    private(set) var history = ChallengeHistory(exercises: [], sets: [], calendar: .current)
    private(set) var sessionID: UUID?
    private(set) var sessionStart: Date?
    private(set) var sessionHeartRate: Int?
    @ObservationIgnored private var sessionHeart: [HeartSample] = []

    private static let baselineKey = "challengeBaseline"
    /// Progress from before the app (entered once in settings).
    private(set) var baseline: ChallengeBaseline? = UserDefaults.standard.data(forKey: ChallengeModel.baselineKey)
        .flatMap { try? JSONDecoder().decode(ChallengeBaseline.self, from: $0) }

    var isSetUp: Bool { !exercises.isEmpty }

    /// "Push-ups 40 · Squats 60" for today (Live Activity).
    var repsToday: String {
        exercises.map { "\($0.name) \(history.total(of: $0.id, on: .now))" }.joined(separator: " · ")
    }
    var isSessionRunning: Bool { sessionID != nil }

    init(store: ChallengeStore) {
        self.store = store
        // A session the app was killed in: closed at its last set and exported with the next sync.
        _ = try? store.closeOpenSessions()
        reload()
    }

    func reload() {
        exercises = (try? store.exercises()) ?? []
        let all = (try? store.exercises(includeArchived: true)) ?? []
        history = ChallengeHistory(exercises: all, sets: (try? store.sets()) ?? [], calendar: .current, baseline: baseline)
    }

    func setBaseline(_ new: ChallengeBaseline?) {
        baseline = new
        UserDefaults.standard.set(new.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.baselineKey)
        reload()
    }

    func setUp(_ items: [(name: String, unit: ExerciseUnit, target: Int)]) {
        for item in items { try? store.addExercise(name: item.name, unit: item.unit, target: item.target, at: .now) }
        reload()
    }

    func log(_ count: Int, to exerciseID: UUID) {
        try? store.log(count, exerciseID: exerciseID, at: .now, sessionID: sessionID)
        reload()
    }

    func canUndo(_ exerciseID: UUID) -> Bool { history.total(of: exerciseID, on: .now) > 0 }

    func undo(_ exerciseID: UUID) {
        _ = try? store.undoLast(exerciseID: exerciseID, on: .now)
        reload()
    }

    func add(name: String, unit: ExerciseUnit, target: Int, autoStep: Int = 0, autoWeekday: Int? = nil) {
        try? store.addExercise(name: name, unit: unit, target: target, autoStep: autoStep, autoWeekday: autoWeekday, at: .now)
        reload()
    }

    func setTarget(_ exerciseID: UUID, target: Int, autoStep: Int, autoWeekday: Int?) {
        try? store.setTarget(exerciseID, target: target, autoStep: autoStep, autoWeekday: autoWeekday, at: .now)
        reload()
    }

    func rename(_ exerciseID: UUID, to name: String) { try? store.rename(exerciseID, to: name); reload() }
    func archive(_ exerciseID: UUID) { try? store.archive(exerciseID, at: .now); reload() }
    func reorder(_ ids: [UUID]) { try? store.reorder(ids); reload() }

    // MARK: Timed session

    func startSession() {
        let now = Date()
        guard sessionID == nil, let id = try? store.startSession(at: now) else { return }
        sessionID = id
        sessionStart = now
        sessionHeart = []
        sessionHeartRate = nil
        onSessionChange?()
        note?("challenge session started")
    }

    func addHeartRate(_ bpm: Int) {
        guard sessionID != nil, bpm > 0 else { return }
        sessionHeartRate = bpm
        sessionHeart.append(HeartSample(date: .now, bpm: bpm))
    }

    func finishSession() async {
        guard let id = sessionID else { return }
        try? store.finishSession(id, at: .now, heart: sessionHeart)
        endSession()
        note?("challenge session finished")
        await exportPendingSessions()
    }

    func cancelSession() {
        guard let id = sessionID else { return }
        try? store.cancelSession(id)
        endSession()
        note?("challenge session cancelled")
    }

    private func endSession() {
        sessionID = nil
        sessionStart = nil
        sessionHeartRate = nil
        sessionHeart = []
        onSessionChange?()
        reload()
    }

    /// One export at a time; a session finished meanwhile is picked up right after. Failures stay
    /// queued for the next Health export.
    func exportPendingSessions() async {
        guard !isExporting else { exportAgain = true; return }
        isExporting = true
        defer { isExporting = false }
        repeat {
            exportAgain = false
            await exportOnce()
        } while exportAgain
    }

    private func exportOnce() async {
        for session in (try? store.pendingSessions()) ?? [] {
            do {
                try await exporter.export(session)
                try? store.markSessionExported(session.id)
                note?("challenge session exported to Health")
            } catch {
                note?("challenge session export failed: \(logText(error))")
            }
        }
    }
}
