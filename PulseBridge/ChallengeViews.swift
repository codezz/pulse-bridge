import PulseKit
import SwiftUI

extension ExerciseUnit {
    var short: String { self == .reps ? "reps" : "s" }
    var title: String { self == .reps ? "Reps" : "Seconds" }
}

/// Summary card: one ring per exercise, the streak, and the way into logging and history.
struct ChallengeCard: View {
    let model: ChallengeModel
    let onLog: () -> Void
    @State private var showSetup = false

    private var history: ChallengeHistory { model.history }

    var body: some View {
        Card(title: "Daily challenge", systemImage: "figure.strengthtraining.traditional", color: .orange) {
            if model.isSetUp {
                HStack(spacing: 18) {
                    ForEach(model.exercises) { exercise in
                        ring(exercise)
                    }
                    Spacer(minLength: 0)
                }
                streakLine
                HStack {
                    Button(action: onLog) {
                        Label("Log", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    NavigationLink(value: SummaryRoute.challengeHistory) {
                        Label("History", systemImage: "calendar").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    ChallengeShareButton(model: model)
                        .buttonStyle(.bordered)
                }
            } else {
                Text("Track a daily goal like push-ups and squats, with streaks and history.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Set up challenge") { showSetup = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .sheet(isPresented: $showSetup) { ChallengeSetupView(model: model) }
    }

    private func ring(_ exercise: ExerciseInfo) -> some View {
        let total = history.total(of: exercise.id, on: .now)
        let target = history.target(of: exercise, on: .now) ?? 0
        return VStack(spacing: 6) {
            ProgressRing(progress: target > 0 ? Double(total) / Double(target) : 0, color: .orange) {
                VStack(spacing: 0) {
                    Text("\(total)").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("/\(target)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(exercise.name).font(.caption).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(total) of \(target) \(exercise.unit.short)")
    }

    @ViewBuilder private var streakLine: some View {
        let streak = history.streak(today: .now)
        let best = history.bestStreak(today: .now)
        if history.status(on: .now) == .done {
            Label("Done for today · \(streak)-day streak", systemImage: "checkmark.seal.fill")
                .font(.subheadline.bold()).foregroundStyle(.green)
        } else {
            Text(streak > 0 ? "🔥 \(streak)-day streak · best \(best)" : "Start a streak today")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// First setup, pre-filled with the current challenge.
struct ChallengeSetupView: View {
    let model: ChallengeModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = [Row(name: "Push-ups", target: 60), Row(name: "Squats", target: 60)]

    struct Row: Identifiable {
        let id = UUID()
        var name: String
        var unit = ExerciseUnit.reps
        var target: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading) {
                            TextField("Exercise", text: $row.name)
                            Stepper(value: $row.target, in: 1...1000, step: 5) {
                                Text("\(row.target) \(row.unit.short) a day")
                            }
                            Picker("Unit", selection: $row.unit) {
                                ForEach(ExerciseUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }
                    Button("Add exercise", systemImage: "plus") { rows.append(Row(name: "", target: 20)) }
                } footer: {
                    Text("You can change targets any time, and let them grow every week.")
                }
            }
            .navigationTitle("Daily challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        model.setUp(validRows.map { ($0.name, $0.unit, $0.target) })
                        dismiss()
                    }
                    .disabled(validRows.isEmpty)
                }
            }
        }
    }

    private var validRows: [Row] {
        rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// Log sets through the day, optionally inside a timed session that goes to Health.
struct ChallengeLogger: View {
    let model: ChallengeModel
    let coordinator: SyncCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var customFor: ExerciseInfo?
    @State private var customText = ""

    private var history: ChallengeHistory { model.history }
    private var totalToday: Int { model.exercises.reduce(0) { $0 + history.total(of: $1.id, on: .now) } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.exercises) { exercise in
                    exerciseSection(exercise)
                }
                sessionSection
            }
            .navigationTitle("Log sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ChallengeSettingsView(model: model) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Exercises and targets")
                }
            }
            .alert("Log \(customFor?.name ?? "")", isPresented: Binding(get: { customFor != nil }, set: { if !$0 { customFor = nil } })) {
                TextField("Count", text: $customText).keyboardType(.numberPad)
                Button("Log") {
                    if let exercise = customFor, let count = Int(customText), count > 0 { model.log(count, to: exercise.id) }
                    customText = ""
                }
                Button("Cancel", role: .cancel) { customText = "" }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: totalToday)
            .sensoryFeedback(.success, trigger: history.status(on: .now) == .done) { _, done in done }
        }
    }

    private func exerciseSection(_ exercise: ExerciseInfo) -> some View {
        let total = history.total(of: exercise.id, on: .now)
        let target = history.target(of: exercise, on: .now) ?? 0
        return Section(exercise.name) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(total)").numberFont(34)
                Text("/ \(target) \(exercise.unit.short)").foregroundStyle(.secondary)
                Spacer()
                if total >= target && target > 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
                }
            }
            ProgressView(value: Double(min(total, max(target, 1))), total: Double(max(target, 1))).tint(.orange)
            HStack {
                ForEach([5, 10, 20], id: \.self) { step in
                    Button("+\(step)") { model.log(step, to: exercise.id) }
                        .buttonStyle(.bordered).tint(.orange)
                        .frame(maxWidth: .infinity)
                }
                Button("Custom") { customFor = exercise }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            Button("Undo last", systemImage: "arrow.uturn.backward") { model.undo(exercise.id) }
                .disabled(!model.canUndo(exercise.id))
        }
    }

    @ViewBuilder private var sessionSection: some View {
        Section {
            if let start = model.sessionStart {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Text(clockText(context.date.timeIntervalSince(start))).numberFont(34).monospacedDigit()
                        Spacer()
                        Label(model.sessionHeartRate.map { "\($0) bpm" } ?? "-", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                Button("Finish session") { Task { await model.finishSession() } }
                    .buttonStyle(.borderedProminent).tint(.orange)
                Button("Cancel session", role: .destructive) { model.cancelSession() }
            } else {
                Button("Start timed session", systemImage: "timer") { model.startSession() }
            }
        } header: {
            Text("Session")
        } footer: {
            if model.sessionStart == nil {
                Text("Times your sets and saves a Strength training workout with band heart rate to Apple Health."
                     + (coordinator.band.state == .connected ? "" : " Band not connected: no heart rate."))
            }
        }
    }
}

struct ChallengeSettingsView: View {
    let model: ChallengeModel
    var body: some View { Text("Settings") }
}

struct ChallengeShareButton: View {
    let model: ChallengeModel
    var body: some View { EmptyView() }
}
