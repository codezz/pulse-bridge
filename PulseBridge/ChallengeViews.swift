import PulseKit
import SwiftUI

extension ExerciseUnit {
    var short: String { self == .reps ? String(localized: "reps") : String(localized: "s", comment: "seconds, short") }
    var title: String { self == .reps ? String(localized: "Reps") : String(localized: "Seconds") }
}

/// "Monday" for Calendar weekday 2.
func weekdayName(_ weekday: Int) -> String { Calendar.current.weekdaySymbols[weekday - 1] }

/// Summary card: one ring per exercise, the streak, and the way into logging and history.
struct ChallengeCard: View {
    let model: ChallengeModel
    /// The day shown; past days are read-only.
    var day = Date.now
    /// Opens the Challenge tab (logging, history).
    let onOpen: () -> Void
    @State private var showSetup = false

    private var history: ChallengeHistory { model.history }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Card(title: "Daily challenge", systemImage: "figure.strengthtraining.traditional", color: Palette.challenge) {
            if model.isSetUp {
                HStack(spacing: 18) {
                    ForEach(history.exercises.filter { history.isActive($0, on: day) }) { exercise in
                        ring(exercise)
                    }
                    Spacer(minLength: 0)
                }
                if isToday {
                    streakLine
                    buttons
                } else {
                    pastDayLine
                }
            } else {
                Text("Track a daily goal like push-ups and squats, with streaks and history.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Set up challenge") { showSetup = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.challenge)
            }
        }
        .sheet(isPresented: $showSetup) { ChallengeSetupView(model: model) }
    }

    @ViewBuilder private var pastDayLine: some View {
        switch history.status(on: day) {
        case .done: Label("Done", systemImage: "checkmark.seal.fill").font(.subheadline.bold()).foregroundStyle(.green)
        case .partial: Text("Partly done").font(.subheadline).foregroundStyle(.secondary)
        case .none: Text(history.isBeforeTracking(day) ? "Before the app" : "Nothing logged").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack {
            Button(action: onOpen) {
                Label("Log sets", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.challenge)
            ChallengeShareButton(model: model)
                .buttonStyle(.bordered)
        }
    }

    private func ring(_ exercise: ExerciseInfo) -> some View {
        let progress = history.progress(of: exercise, on: day)
        return VStack(spacing: 6) {
            ProgressRing(progress: progress.fraction, color: Palette.challenge) {
                VStack(spacing: 0) {
                    Text("\(progress.total)").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("/\(progress.target)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(exercise.name).font(.caption).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(progress.total) of \(progress.target) \(exercise.unit.short)")
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
    @State private var rows: [Row] = [Row(name: String(localized: "Push-ups"), target: 60), Row(name: String(localized: "Squats"), target: 60)]

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
                        model.setUp(validRows.map { ($0.name.trimmingCharacters(in: .whitespaces), $0.unit, $0.target) })
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

/// A set just logged, for the undo banner.
struct LoggedSet: Equatable {
    let id = UUID()
    let exercise: ExerciseInfo
    let count: Int
}

/// Today in one card: the streak line, one compact row per exercise and the session start.
struct ChallengeTodayCard: View {
    let model: ChallengeModel
    let coordinator: SyncCoordinator
    @Binding var lastSet: LoggedSet?
    @State private var customFor: ExerciseInfo?
    @State private var customText = ""

    private var history: ChallengeHistory { model.history }
    private var totalToday: Int { model.exercises.reduce(0) { $0 + history.total(of: $1.id, on: .now) } }

    var body: some View {
        Card(title: "Today", systemImage: "figure.strengthtraining.traditional", color: Palette.challenge) {
            ChallengeStatsLine(history: history)
            ForEach(model.exercises) { exercise in
                Divider()
                ExerciseLogRow(model: model, exercise: exercise, log: { log($0, exercise) },
                               custom: { customFor = exercise }, undo: { undo(exercise) })
            }
            if !model.isSessionRunning {
                Divider()
                sessionRow
            }
        }
        .celebrates(history.status(on: .now) == .done, context: Calendar.current.startOfDay(for: .now))
        .sensoryFeedback(.impact(weight: .light), trigger: totalToday)
        .alert("Log \(customFor?.name ?? "")", isPresented: Binding(get: { customFor != nil }, set: { if !$0 { customFor = nil } })) {
            TextField("Count", text: $customText).keyboardType(.numberPad)
            Button("Log") {
                if let exercise = customFor, let count = Int(customText), ChallengeStore.countRange.contains(count) {
                    log(count, exercise)
                }
                customText = ""
            }
            Button("Cancel", role: .cancel) { customText = "" }
        }
    }

    private var sessionRow: some View {
        Button { model.startSession() } label: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    sessionTitle
                    Spacer()
                    sessionNote
                }
                VStack(alignment: .leading, spacing: 2) {
                    sessionTitle
                    sessionNote
                }
            }
        }
        .tint(Palette.challenge)
        .accessibilityHint("Times your sets and saves a Strength training workout with band heart rate to Apple Health.")
    }

    private var sessionTitle: some View {
        Label("Start timed session", systemImage: "timer").font(.subheadline.bold()).fixedSize()
    }

    private var sessionNote: some View {
        Text(coordinator.band.state == .connected ? "Saved to Health" : "No band: no heart rate")
            .font(.caption).foregroundStyle(Color(.secondaryLabel)).fixedSize()
    }

    private func log(_ count: Int, _ exercise: ExerciseInfo) {
        model.log(count, to: exercise.id)
        lastSet = LoggedSet(exercise: exercise, count: count)
    }

    private func undo(_ exercise: ExerciseInfo) {
        model.undo(exercise.id)
        lastSet = nil
    }
}

/// "🔥 2 best 14 · 34/39 days · 87% hit" in one line.
struct ChallengeStatsLine: View {
    let history: ChallengeHistory

    var body: some View {
        let streak = history.streak(today: .now)
        let best = history.bestStreak(today: .now)
        let done = history.daysDone(today: .now)
        let day = history.challengeDay(today: .now)
        let rate = Int((history.successRate(today: .now) * 100).rounded())
        let stats = Group {
            stat("flame.fill", "\(streak)", best > streak ? "best \(best)" : "day streak")
                .accessibilityLabel("\(streak) day streak, best \(max(best, streak))")
            stat("calendar", "\(done)", "of \(day) days")
                .accessibilityLabel("\(done) of \(day) days done")
            stat("target", "\(rate)%", "hit")
                .accessibilityLabel("\(rate) percent of days hit")
        }
        // One line when it fits, otherwise one stat per line (large text).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { stats }
            VStack(alignment: .leading, spacing: 4) { stats }
        }
    }

    private func stat(_ symbol: String, _ value: String, _ note: LocalizedStringResource) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(Palette.challenge).font(.caption)
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
    }
}

/// One exercise on one line: a small ring, "40/60 reps", +5 / +10 / +20 and a menu with a custom
/// count and undo. Done exercises keep the menu only (with the quick amounts in it). Falls back to two
/// lines when the text is large.
private struct ExerciseLogRow: View {
    let model: ChallengeModel
    let exercise: ExerciseInfo
    let log: (Int) -> Void
    let custom: () -> Void
    let undo: () -> Void

    private static let steps = [5, 10, 20]
    private var progress: ChallengeProgress { model.history.progress(of: exercise, on: .now) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                summary
                Spacer(minLength: 4)
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                summary
                HStack {
                    controls
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            ProgressRing(progress: progress.fraction, color: progress.isDone ? .green : Palette.challenge, size: 36) {
                if progress.isDone { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green) }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name).font(.subheadline.bold()).lineLimit(1)
                Text("\(progress.total)/\(progress.target) \(exercise.unit.short)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(progress.isDone ? .green : .secondary)
            }
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(progress.total) of \(progress.target) \(exercise.unit.short)"
                            + (progress.isDone ? ", done" : ", \(progress.target - progress.total) to go"))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if !progress.isDone {
                ForEach(Self.steps, id: \.self) { step in
                    Button("+\(step)") { log(step) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                        .tint(Palette.challenge)
                        .accessibilityLabel("Add \(step) \(exercise.name)")
                }
            }
            Menu {
                if progress.isDone {
                    ForEach(Self.steps, id: \.self) { step in
                        Button("Add \(step)") { log(step) }
                    }
                }
                Button("Custom amount", systemImage: "number", action: custom)
                Button("Undo last set", systemImage: "arrow.uturn.backward", action: undo)
                    .disabled(!model.canUndo(exercise.id))
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Palette.challenge)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("More for \(exercise.name)")
        }
    }
}

/// Pinned to the bottom while a timed session runs: timer, band heart rate, Finish, and Cancel in
/// the menu. Sessions go to Health as Strength training workouts.
struct ChallengeSessionBar: View {
    let model: ChallengeModel
    let start: Date

    var body: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(clockText(context.date.timeIntervalSince(start))).numberFont(22).monospacedDigit()
            }
            Label(model.sessionHeartRate.map { "\($0)" } ?? "-", systemImage: "heart.fill")
                .font(.subheadline.bold()).monospacedDigit()
                .foregroundStyle(Palette.heart)
                .accessibilityLabel(model.sessionHeartRate.map { String(localized: "Heart rate \($0)") } ?? String(localized: "No heart rate"))
            Spacer(minLength: 0)
            Menu {
                Button("Cancel session", systemImage: "xmark", role: .destructive) { model.cancelSession() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("Session options")
            Button("Finish") { Task { await model.finishSession() } }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        .tint(Palette.challenge)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "+10 Push-ups · Undo" for a few seconds after a set.
struct UndoBanner: View {
    let set: LoggedSet
    let undo: () -> Void

    var body: some View {
        HStack {
            Text("+\(set.count) \(set.exercise.name)").font(.subheadline.bold())
            Spacer()
            Button("Undo", action: undo).font(.subheadline.bold()).tint(Palette.challenge)
                .accessibilityLabel("Undo \(set.count) \(set.exercise.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Exercises and their targets: reorder, archive, add, edit.
struct ChallengeSettingsView: View {
    let model: ChallengeModel
    @State private var archiving: ExerciseInfo?

    var body: some View {
        List {
            Section {
                ForEach(model.exercises) { exercise in
                    NavigationLink { ExerciseEditor(model: model, exercise: exercise) } label: {
                        LabeledContent(exercise.name, value: targetText(exercise))
                    }
                    .swipeActions { Button("Archive") { archiving = exercise }.tint(Palette.challenge) }
                }
                .onMove { from, to in
                    var ids = model.exercises.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    model.reorder(ids)
                }
            } footer: {
                Text("Archived exercises leave the card and the logger; their history stays.")
            }
            Section {
                NavigationLink { BaselineEditor(model: model) } label: {
                    LabeledContent("Progress before the app", value: model.baseline.map { String(localized: "\($0.daysDoneBefore) days") } ?? String(localized: "None"))
                }
            } footer: {
                Text("Started before using Pulse Bridge? Bring over your days done and streaks.")
            }
        }
        .navigationTitle("Exercises")
        .toolbar {
            EditButton()
            NavigationLink { ExerciseEditor(model: model, exercise: nil) } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add exercise")
        }
        .confirmationDialog("Archive \(archiving?.name ?? "")?", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }),
                            titleVisibility: .visible) {
            Button("Archive", role: .destructive) { if let archiving { model.archive(archiving.id) } }
        }
    }

    private func targetText(_ exercise: ExerciseInfo) -> String {
        let target = model.history.target(of: exercise, on: .now) ?? 0
        guard let change = exercise.latestChange, change.autoStep != 0, let weekday = change.autoWeekday else {
            return "\(target) \(exercise.unit.short)"
        }
        return String(localized: "\(target) \(exercise.unit.short), +\(change.autoStep) every \(weekdayName(weekday))")
    }
}

/// Numbers from before the app: when the challenge started, days done, streak and best streak up to
/// the day before the first day tracked here.
struct BaselineEditor: View {
    let model: ChallengeModel
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var daysDone = 0
    @State private var streak = 0
    @State private var best = 0
    @State private var averages: [UUID: Int] = [:]

    private var firstTracked: Date { model.history.firstTrackedDay }

    var body: some View {
        Form {
            Section {
                DatePicker("Challenge started", selection: $start, in: ...firstTracked, displayedComponents: .date)
                numberRow(String(localized: "Days done"), $daysDone)
                numberRow(String(localized: "Streak"), $streak)
                numberRow(String(localized: "Best streak"), $best)
            } footer: {
                Text("Up to \(dayBefore.formatted(date: .abbreviated, time: .omitted)), the day before your first day in the app. Days you complete here add to these.")
            }
            Section {
                ForEach(model.exercises) { exercise in
                    numberRow(exercise.name, Binding(get: { averages[exercise.id] ?? 0 }, set: { averages[exercise.id] = $0 }))
                }
            } header: {
                Text("Average per day")
            } footer: {
                Text("A rough number is fine: it's multiplied by the days done and added to each exercise's all-time total.")
            }
            if model.baseline != nil {
                Section {
                    Button("Remove", role: .destructive) {
                        model.setBaseline(nil)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Before the app")
        .toolbar {
            Button("Save") {
                model.setBaseline(ChallengeBaseline(startDate: start, daysDoneBefore: daysDone, streakBefore: streak,
                                                    bestBefore: max(best, streak), averagePerDay: averages.filter { $0.value > 0 }))
                dismiss()
            }
        }
        .onAppear {
            guard let baseline = model.baseline else {
                start = Calendar.current.date(byAdding: .day, value: -1, to: firstTracked) ?? firstTracked
                return
            }
            start = baseline.startDate
            daysDone = baseline.daysDoneBefore
            streak = baseline.streakBefore
            best = baseline.bestBefore
            averages = baseline.averagePerDay
        }
    }

    private var dayBefore: Date { Calendar.current.date(byAdding: .day, value: -1, to: firstTracked) ?? firstTracked }

    private func numberRow(_ title: String, _ value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Add an exercise, or change one's name, target and weekly growth.
struct ExerciseEditor: View {
    let model: ChallengeModel
    let exercise: ExerciseInfo?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = ExerciseUnit.reps
    @State private var target = 20
    @State private var grows = false
    @State private var step = 5
    @State private var weekday = 2

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                if exercise == nil {
                    Picker("Unit", selection: $unit) {
                        ForEach(ExerciseUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Stepper(value: $target, in: 1...2000, step: 5) { Text("Daily target: \(target) \(unit.short)") }
            }
            Section {
                Toggle("Grow automatically", isOn: $grows)
                if grows {
                    Stepper(value: $step, in: 1...50) { Text("+\(step) every week") }
                    Picker("On", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(weekdayName($0)).tag($0) }
                    }
                }
            } footer: {
                Text("The daily target is how many you aim for each day; a day counts as done when every exercise reaches it. Changes start today and past days keep the target they had. With growth on, the target goes up by itself every week.")
            }
        }
        .navigationTitle(exercise == nil ? "New exercise" : "Edit exercise")
        .toolbar {
            Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let exercise else { return }
        name = exercise.name
        unit = exercise.unit
        target = model.history.target(of: exercise, on: .now) ?? 20
        if let change = exercise.latestChange, change.autoStep != 0, let day = change.autoWeekday {
            grows = true
            step = change.autoStep
            weekday = day
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let exercise {
            if trimmed != exercise.name { model.rename(exercise.id, to: trimmed) }
            model.setTarget(exercise.id, target: target, autoStep: grows ? step : 0, autoWeekday: grows ? weekday : nil)
        } else {
            model.add(name: trimmed, unit: unit, target: target, autoStep: grows ? step : 0, autoWeekday: grows ? weekday : nil)
        }
        dismiss()
    }
}

/// Shares today's numbers as a text message, in the app's language.
struct ChallengeShareButton: View {
    let model: ChallengeModel

    var body: some View {
        ShareLink(item: ChallengeShareText.make(model.history.shareSummary(today: .now))) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
    }
}
