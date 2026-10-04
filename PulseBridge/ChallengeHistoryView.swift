import Charts
import PulseKit
import SwiftUI

/// Month calendar, streaks, totals and how targets grew.
struct ChallengeHistoryView: View {
    let model: ChallengeModel
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?
    @ScaledMetric(relativeTo: .caption) private var cellSize: CGFloat = 32

    private var history: ChallengeHistory { model.history }
    private var calendar: Calendar { .current }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top) {
                    let streak = history.streak(today: .now)
                    let best = history.bestStreak(today: .now)
                    stat("🔥 \(streak)", "day streak", note: best > streak ? "best \(best)" : nil)
                    stat("\(history.daysDone(today: .now))", "days done", note: "of \(history.challengeDay(today: .now))")
                    stat(totalText, "total", note: "since \(history.firstTrackedDay.formatted(.dateTime.day().month(.abbreviated)))")
                }
            }
            Section { monthGrid } header: { monthHeader }
            Section("Totals") {
                ForEach(model.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.headline)
                        Text(totals(exercise)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Targets") {
                ForEach(model.exercises) { exercise in
                    if targetHasChanged(exercise) {
                        VStack(alignment: .leading) {
                            Text(exercise.name).font(.subheadline)
                            targetChart(exercise).frame(height: 100)
                        }
                    } else {
                        LabeledContent(exercise.name, value: steadyTargetText(exercise))
                    }
                }
            }
        }
        .navigationTitle("Challenge")
        .toolbar {
            ChallengeShareButton(model: model)
            NavigationLink { ChallengeSettingsView(model: model) } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Exercises and targets")
        }
        .sheet(item: Binding(get: { selectedDay.map(DayItem.init) }, set: { selectedDay = $0?.day })) { item in
            DaySheet(model: model, day: item.day).presentationDetents([.medium])
        }
    }

    private func stat(_ value: String, _ label: String, note: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).numberFont(28).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// All logged reps (and seconds, if a timed exercise exists), across exercises.
    private var totalText: String {
        let all = DateInterval(start: .distantPast, end: .distantFuture)
        func sum(_ unit: ExerciseUnit) -> Int {
            history.exercises.filter { $0.unit == unit }.reduce(0) { $0 + history.total(of: $1.id, in: all) }
        }
        let reps = sum(.reps), seconds = sum(.seconds)
        return seconds > 0 ? "\(reps) · \(seconds)s" : "\(reps)"
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).textCase(nil)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
                .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
    }

    private func shiftMonth(_ by: Int) {
        month = calendar.date(byAdding: .month, value: by, to: month)!
    }

    /// Weeks start on Monday; leading blanks align the first day.
    private var monthGrid: some View {
        let days = calendar.range(of: .day, in: .month, for: month)!.map { calendar.date(byAdding: .day, value: $0 - 1, to: month)! }
        let blanks = (calendar.component(.weekday, from: month) + 5) % 7
        let symbols = ["M", "T", "W", "T", "F", "S", "S"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { Text($0.element).font(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: cellSize) }
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let kind = cellKind(day)
        Button { selectedDay = day } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption.bold())
                .frame(width: cellSize, height: cellSize)
                .background(Circle().fill(kind == .tracked ? statusColor(history.status(on: day)) : .clear))
                .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(kind == .beforeTracking ? Color.secondary : .clear))
                .overlay(Circle().stroke(isToday ? Color.orange : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(kind != .tracked)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(cellLabel(day, kind))")
    }

    private enum CellKind { case tracked, beforeTracking, outside }

    /// Tracked days get a status circle; days before the app (with a baseline) a dashed ring; days
    /// before the challenge or in the future nothing.
    private func cellKind(_ day: Date) -> CellKind {
        if day > .now { return .outside }
        if history.isBeforeTracking(day) { return .beforeTracking }
        return day >= history.firstTrackedDay ? .tracked : .outside
    }

    private func cellLabel(_ day: Date, _ kind: CellKind) -> String {
        switch kind {
        case .tracked: statusText(history.status(on: day))
        case .beforeTracking: "before the app"
        case .outside: "not part of the challenge"
        }
    }

    private func statusText(_ status: DayStatus) -> String {
        switch status {
        case .done: "done"
        case .partial: "partial"
        case .none: "nothing logged"
        }
    }

    private func totals(_ exercise: ExerciseInfo) -> String {
        let week = history.week(containing: .now)
        let month = calendar.dateInterval(of: .month, for: .now)!
        let all = DateInterval(start: .distantPast, end: .distantFuture)
        return "This week \(history.total(of: exercise.id, in: week)) · This month \(history.total(of: exercise.id, in: month)) · All time \(history.total(of: exercise.id, in: all))"
    }

    /// A chart only once there's a change to draw: more than one target, or weekly growth.
    private func targetHasChanged(_ exercise: ExerciseInfo) -> Bool {
        Set(exercise.changes.map(\.target)).count > 1 || history.target(of: exercise, on: .now) != exercise.changes.first?.target
    }

    /// "60 reps a day since 4 Oct", plus the growth rule if there is one.
    private func steadyTargetText(_ exercise: ExerciseInfo) -> String {
        let target = history.target(of: exercise, on: .now) ?? 0
        let since = (exercise.changes.first?.day ?? exercise.createdAt).formatted(.dateTime.day().month(.abbreviated))
        var text = "\(target) \(exercise.unit.short) a day since \(since)"
        if let change = exercise.latestChange, change.autoStep != 0, let weekday = change.autoWeekday {
            text += ", +\(change.autoStep) every \(weekdayName(weekday))"
        }
        return text
    }

    private func targetChart(_ exercise: ExerciseInfo) -> some View {
        let start = max(calendar.startOfDay(for: exercise.createdAt), calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: .now))!)
        // Calendar days (not 86400 s), so a daylight-saving change doesn't skip or repeat one.
        let count = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: .now)).day ?? 0
        let points = (0...max(0, count)).compactMap { offset -> (day: Date, target: Int)? in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return history.target(of: exercise, on: day).map { (day, $0) }
        }
        return Chart(points, id: \.day) {
            LineMark(x: .value("Day", $0.day), y: .value("Target", $0.target)).interpolationMethod(.stepEnd)
        }
        .foregroundStyle(.orange)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

private struct DayItem: Identifiable {
    let day: Date
    var id: Date { day }
}

/// One day's sets and targets.
private struct DaySheet: View {
    let model: ChallengeModel
    let day: Date

    var body: some View {
        NavigationStack {
            List {
                // Active that day, or with sets that day (e.g. archived that evening).
                ForEach(model.history.exercises.filter { model.history.isActive($0, on: day) || model.history.total(of: $0.id, on: day) > 0 }) { exercise in
                    let sets = model.history.sets(on: day).filter { $0.exerciseID == exercise.id }
                    Section("\(exercise.name) · \(model.history.total(of: exercise.id, on: day)) / \(model.history.target(of: exercise, on: day) ?? 0)") {
                        if sets.isEmpty {
                            Text("Nothing logged").foregroundStyle(.secondary)
                        }
                        ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                            LabeledContent(set.date.formatted(date: .omitted, time: .shortened), value: "\(set.count) \(exercise.unit.short)")
                        }
                    }
                }
            }
            .navigationTitle(day.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
