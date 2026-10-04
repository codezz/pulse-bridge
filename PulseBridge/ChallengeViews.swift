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
        let progress = history.progress(of: exercise, on: .now)
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
    }

    private func exerciseSection(_ exercise: ExerciseInfo) -> some View {
        let progress = history.progress(of: exercise, on: .now)
        return Section(exercise.name) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(progress.total)").numberFont(34)
                Text("/ \(progress.target) \(exercise.unit.short)").foregroundStyle(.secondary)
                Spacer()
                if progress.isDone {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Done")
                }
            }
            ProgressView(value: min(progress.fraction, 1)).tint(.orange)
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
                Text("Changes start today. Past days keep the target they had.")
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
