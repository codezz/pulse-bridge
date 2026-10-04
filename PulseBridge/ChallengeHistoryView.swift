import Charts
import PulseKit
import SwiftUI

/// Month calendar, streaks, totals and how targets grew.
struct ChallengeHistoryView: View {
    let model: ChallengeModel
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?

    private var history: ChallengeHistory { model.history }
    private var calendar: Calendar { .current }

    var body: some View {
        List {
            Section("Streak") {
                HStack {
                    stat("\(history.streak(today: .now))", "current")
                    stat("\(history.bestStreak(today: .now))", "best")
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
                    VStack(alignment: .leading) {
                        Text(exercise.name).font(.subheadline)
                        targetChart(exercise).frame(height: 100)
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

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).numberFont(34)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
            ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 32) }
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
        let future = day > .now
        let isToday = calendar.isDateInToday(day)
        Button { selectedDay = day } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.caption.bold())
                .frame(width: 32, height: 32)
                .background(Circle().fill(future ? .clear : statusColor(history.status(on: day))))
                .overlay(Circle().stroke(isToday ? Color.orange : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(statusText(history.status(on: day)))")
    }

    private func statusText(_ status: DayStatus) -> String {
        switch status {
        case .done: "done"
        case .partial: "partial"
        case .none: "nothing logged"
        }
    }

    private func totals(_ exercise: ExerciseInfo) -> String {
        let week = calendar.dateInterval(of: .weekOfYear, for: .now)!
        let month = calendar.dateInterval(of: .month, for: .now)!
        let all = DateInterval(start: .distantPast, end: .distantFuture)
        return "This week \(history.total(of: exercise.id, in: week)) · This month \(history.total(of: exercise.id, in: month)) · All time \(history.total(of: exercise.id, in: all))"
    }

    private func targetChart(_ exercise: ExerciseInfo) -> some View {
        let start = max(calendar.startOfDay(for: exercise.createdAt), calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: .now))!)
        let points = stride(from: start, through: .now, by: 86400).compactMap { day in
            history.target(of: exercise, on: day).map { (day: day, target: $0) }
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
                ForEach(model.history.exercises.filter { model.history.isActive($0, on: day) }) { exercise in
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
