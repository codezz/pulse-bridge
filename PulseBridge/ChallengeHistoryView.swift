import Charts
import PulseKit
import SwiftUI

/// The Challenge tab's screen: today's logging and session, then streaks, the month calendar and
/// a card per exercise.
struct ChallengeHistoryView: View {
    let model: ChallengeModel
    let coordinator: SyncCoordinator
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?
    @ScaledMetric(relativeTo: .caption) private var cellSize: CGFloat = 32

    private var history: ChallengeHistory { model.history }
    private var calendar: Calendar { .current }

    var body: some View {
        List {
            ChallengeLogSections(model: model, coordinator: coordinator)
            Section {
                HStack(alignment: .top) {
                    let streak = history.streak(today: .now)
                    let best = history.bestStreak(today: .now)
                    stat("🔥 \(streak)", "day streak", note: best > streak ? "best \(best)" : nil)
                    stat("\(history.daysDone(today: .now))", "days done", note: "of \(history.challengeDay(today: .now))")
                    stat("\(Int((history.successRate(today: .now) * 100).rounded()))%", "days hit")
                }
            }
            Section { monthGrid } header: { monthHeader }
            ForEach(model.exercises) { exercise in
                Section { ExerciseTotalsCard(history: history, exercise: exercise) }
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
}

/// One exercise: all-time total, the last 14 days against the daily target, and week / month / average.
private struct ExerciseTotalsCard: View {
    let history: ChallengeHistory
    let exercise: ExerciseInfo

    private var calendar: Calendar { .current }

    private struct Day: Identifiable {
        let day: Date
        let total: Int
        let target: Int?
        var id: Date { day }
    }

    private var days: [Day] {
        let today = calendar.startOfDay(for: .now)
        return (0..<14).reversed().compactMap { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            guard day >= history.firstTrackedDay else { return nil }
            return Day(day: day, total: history.total(of: exercise.id, on: day), target: history.target(of: exercise, on: day))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name).font(.headline)
                Spacer()
                Text(history.allTime(of: exercise.id).formatted()).numberFont(28)
                Text("all time").font(.caption).foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value(exercise.unit.short, day.total))
                        .foregroundStyle(day.target.map { day.total >= $0 } ?? false ? Color.orange : Color.orange.opacity(0.4))
                }
                ForEach(days.filter { $0.target != nil }) { day in
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Target", day.target ?? 0))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 90)
            .accessibilityLabel("\(exercise.name), last 14 days against the daily target")
            HStack(spacing: 8) {
                chip("Week", history.total(of: exercise.id, in: history.week(containing: .now)))
                chip("Month", history.total(of: exercise.id, in: calendar.dateInterval(of: .month, for: .now)!))
                chip("Avg/day", history.averagePerDay(of: exercise.id, today: .now))
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.subheadline.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
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
