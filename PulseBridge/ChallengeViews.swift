import PulseKit
import SwiftUI

extension ExerciseUnit {
    var short: String { self == .reps ? "reps" : "s" }
    var title: String { self == .reps ? "Reps" : "Seconds" }
}

/// "Monday" for Calendar weekday 2.
func weekdayName(_ weekday: Int) -> String { Calendar.current.weekdaySymbols[weekday - 1] }

/// Summary card: one ring per exercise, the streak, and the way into logging and history.
struct ChallengeCard: View {
    let model: ChallengeModel
    /// The day shown; past days are read-only.
    var day = Date.now
    let onLog: () -> Void
    /// Opens the Challenge tab.
    let onOpen: () -> Void
    @State private var showSetup = false

    private var history: ChallengeHistory { model.history }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Card(title: "Daily challenge", systemImage: "figure.strengthtraining.traditional", color: Palette.challenge) {
            if model.isSetUp {
                HStack(spacing: 18) {
                    ForEach(model.exercises.filter { history.isActive($0, on: day) }) { exercise in
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
                    .tint(.orange)
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
            Button(action: onLog) {
                Label("Log", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Button(action: onOpen) {
                Label("History", systemImage: "calendar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            ChallengeShareButton(model: model)
                .buttonStyle(.bordered)
        }
    }

    private func ring(_ exercise: ExerciseInfo) -> some View {
        let progress = history.progress(of: exercise, on: day)
        return VStack(spacing: 6) {
            ProgressRing(progress: progress.fraction, color: .orange) {
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

/// Today's sets per exercise (ring, quick buttons, undo) and the timed session, as List sections.
/// Sessions go to Health as Strength training workouts.
struct ChallengeLogSections: View {
    let model: ChallengeModel
    let coordinator: SyncCoordinator
    @State private var customFor: ExerciseInfo?
    @State private var customText = ""

    private var history: ChallengeHistory { model.history }
    private var totalToday: Int { model.exercises.reduce(0) { $0 + history.total(of: $1.id, on: .now) } }

    var body: some View {
        ForEach(model.exercises) { exercise in
            exerciseSection(exercise)
        }
        // On the session section only: modifiers on a group of List sections would repeat per section.
        sessionSection
            .alert("Log \(customFor?.name ?? "")", isPresented: Binding(get: { customFor != nil }, set: { if !$0 { customFor = nil } })) {
                TextField("Count", text: $customText).keyboardType(.numberPad)
                Button("Log") {
                    if let exercise = customFor, let count = Int(customText), ChallengeStore.countRange.contains(count) {
                        model.log(count, to: exercise.id)
                    }
                    customText = ""
                }
                Button("Cancel", role: .cancel) { customText = "" }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: totalToday)
            .sensoryFeedback(.success, trigger: history.status(on: .now) == .done) { _, done in done }
    }

    private func exerciseSection(_ exercise: ExerciseInfo) -> some View {
        let progress = history.progress(of: exercise, on: .now)
        return Section(exercise.name) {
            HStack(spacing: 16) {
                ProgressRing(progress: progress.fraction, color: Palette.challenge, size: 72) {
                    Image(systemName: progress.isDone ? "checkmark" : "figure.strengthtraining.traditional")
                        .font(.title3.bold()).foregroundStyle(progress.isDone ? .green : Palette.challenge)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(progress.total)").numberFont(34)
                        Text("/ \(progress.target) \(exercise.unit.short)").foregroundStyle(.secondary)
                    }
                    Text(progress.isDone ? "Done for today" : "\(max(0, progress.target - progress.total)) to go")
                        .font(.caption).foregroundStyle(progress.isDone ? .green : .secondary)
                }
            }
            .accessibilityElement(children: .combine)
            HStack {
                ForEach([5, 10, 20], id: \.self) { step in
                    Button("+\(step)") { model.log(step, to: exercise.id) }
                        .buttonStyle(.bordered).tint(.orange)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Add \(step) \(exercise.name)")
                }
                Button("Custom") { customFor = exercise }
                    .accessibilityLabel("Custom count for \(exercise.name)")
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
                    .swipeActions { Button("Archive") { archiving = exercise }.tint(.orange) }
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
                    LabeledContent("Progress before the app", value: model.baseline.map { "\($0.daysDoneBefore) days" } ?? "None")
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
        return "\(target) \(exercise.unit.short), +\(change.autoStep) \(weekdayName(weekday))s"
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
                numberRow("Days done", $daysDone)
                numberRow("Streak", $streak)
                numberRow("Best streak", $best)
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

/// The image sent to the friends' group: today's numbers, the streak and the last 7 days.
struct ChallengeShareImage: View {
    let model: ChallengeModel

    var body: some View {
        let history = model.history
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily challenge · \(Date.now.formatted(date: .abbreviated, time: .omitted))")
                .font(.headline).foregroundStyle(.white)
            ForEach(model.exercises) { exercise in
                let progress = history.progress(of: exercise, on: .now)
                HStack {
                    Text(exercise.name).foregroundStyle(.white)
                    Spacer()
                    Text("\(progress.total) / \(progress.target)\(progress.isDone ? " ✓" : "")")
                        .font(.title3.bold()).foregroundStyle(progress.isDone ? .green : .orange)
                }
            }
            Text("🔥 \(history.streak(today: .now))-day streak").font(.subheadline.bold()).foregroundStyle(.white)
            HStack(spacing: 8) {
                ForEach((0..<7).reversed(), id: \.self) { back in
                    let day = Calendar.current.date(byAdding: .day, value: -back, to: .now)!
                    Circle().fill(statusColor(history.status(on: day))).frame(width: 18, height: 18)
                }
            }
            Text("Pulse Bridge").font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .padding(24)
        .frame(width: 360)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }
}

/// Green done, light green partial, gray nothing: shared by the share image and the history calendar.
func statusColor(_ status: DayStatus) -> Color {
    switch status {
    case .done: .green
    case .partial: .green.opacity(0.35)
    case .none: .gray.opacity(0.25)
    }
}

struct ChallengeShareButton: View {
    let model: ChallengeModel
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview("Daily challenge", image: image)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            } else {
                // Same size while the image renders, so the buttons don't jump.
                Image(systemName: "square.and.arrow.up").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .task(id: renderKey) { render() }
    }

    /// Re-render after a set, a target or name change, or a new day.
    private var renderKey: String {
        let exercises = model.exercises.map { "\($0.name):\($0.latestChange?.target ?? 0)" }.joined(separator: ",")
        return "\(model.history.sets.count)|\(exercises)|\(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)"
    }

    private func render() {
        let renderer = ImageRenderer(content: ChallengeShareImage(model: model))
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}
