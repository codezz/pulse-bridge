import Charts
import PulseKit
import SwiftUI

/// The Challenge tab's screen, compact: today's card (streak line, a row per exercise, session
/// start), the calendar (this week, or the month) and a totals row per exercise. A running session
/// and the undo banner sit pinned at the bottom.
struct ChallengeHistoryView: View {
    let model: ChallengeModel
    let coordinator: SyncCoordinator
    @State private var selectedDay: Date?
    @State private var lastSet: LoggedSet?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChallengeTodayCard(model: model, coordinator: coordinator, lastSet: $lastSet)
                ChallengeCalendarCard(history: model.history, selectedDay: $selectedDay)
                ChallengeTotalsCard(history: model.history, exercises: model.exercises)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("Challenge")
        .toolbar {
            ChallengeShareButton(model: model)
            NavigationLink { ChallengeSettingsView(model: model) } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Exercises and targets")
        }
        .sheet(item: Binding(get: { selectedDay.map(DayItem.init) }, set: { selectedDay = $0?.day })) { item in
            DaySheet(model: model, day: item.day).presentationDetents([.medium])
        }
        .task(id: lastSet?.id) {
            guard lastSet != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            withAnimation { lastSet = nil }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let set = lastSet {
                UndoBanner(set: set) {
                    model.undo(set.exercise.id)
                    withAnimation { lastSet = nil }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let start = model.sessionStart {
                ChallengeSessionBar(model: model, start: start)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.snappy, value: lastSet?.id)
        .animation(.snappy, value: model.sessionStart)
    }
}

/// Small rings per day (how much of that day's targets was done): this week, or the whole month.
/// Days before the app (with a baseline) have a dashed ring; tapping a tracked day opens its sets.
private struct ChallengeCalendarCard: View {
    let history: ChallengeHistory
    @Binding var selectedDay: Date?
    @State private var showsMonth = false
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @ScaledMetric(relativeTo: .caption) private var scaledCell: CGFloat = 32
    /// Grows with the text size, but stays inside a seventh of the card.
    private var cellSize: CGFloat { min(scaledCell, 40) }

    private var calendar: Calendar { .current }

    var body: some View {
        Card(title: showsMonth ? month.formatted(.dateTime.month(.wide).year()) : String(localized: "This week"),
             systemImage: "calendar", color: Palette.challenge) {
            grid
            Button {
                withAnimation(.snappy) { showsMonth.toggle() }
            } label: {
                Label(showsMonth ? "Show week" : "Show month", systemImage: showsMonth ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .tint(Palette.challenge)
        } accessory: {
            if showsMonth {
                HStack(spacing: 16) {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous month")
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next month")
                        .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                }
                .font(.subheadline.bold())
                .tint(Palette.challenge)
            }
        }
    }

    private func shiftMonth(_ by: Int) {
        month = calendar.date(byAdding: .month, value: by, to: month)!
    }

    /// Monday first; the month gets leading blanks to align its first day.
    private var grid: some View {
        let days: [Date]
        let blanks: Int
        if showsMonth {
            days = calendar.range(of: .day, in: .month, for: month)!.map { calendar.date(byAdding: .day, value: $0 - 1, to: month)! }
            blanks = (calendar.component(.weekday, from: month) + 5) % 7
        } else {
            let monday = history.week(containing: .now).start
            days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
            blanks = 0
        }
        // The locale's narrow weekday names, Monday first (the list starts on Sunday).
        let narrow = calendar.veryShortStandaloneWeekdaySymbols
        let symbols = Array(narrow[1...] + narrow[..<1])
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { Text($0.element).font(.caption2).foregroundStyle(.secondary) }
            ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: cellSize) }
            ForEach(days, id: \.self) { dayCell($0) }
        }
    }

    @ViewBuilder private func dayCell(_ day: Date) -> some View {
        let kind = cellKind(day)
        let isToday = calendar.isDateInToday(day)
        Button { selectedDay = day } label: {
            ZStack {
                switch kind {
                case .tracked:
                    ProgressRing(progress: history.dayFraction(on: day) ?? 0,
                                 color: history.status(on: day) == .done ? .green : Palette.challenge, size: cellSize) { EmptyView() }
                case .beforeTracking:
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary)
                case .outside:
                    EmptyView()
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption2.weight(isToday ? .heavy : .semibold))
                    .foregroundStyle(isToday ? Palette.challenge : kind == .outside ? .secondary : .primary)
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .disabled(kind != .tracked)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(cellLabel(day, kind))")
    }

    private enum CellKind { case tracked, beforeTracking, outside }

    private func cellKind(_ day: Date) -> CellKind {
        if day > .now { return .outside }
        if history.isBeforeTracking(day) { return .beforeTracking }
        return day >= history.firstTrackedDay ? .tracked : .outside
    }

    private func cellLabel(_ day: Date, _ kind: CellKind) -> String {
        switch kind {
        case .tracked:
            switch history.status(on: day) {
            case .done: String(localized: "done")
            case .partial: String(localized: "partial")
            case .none: String(localized: "nothing logged")
            }
        case .beforeTracking: String(localized: "before the app")
        case .outside: String(localized: "not part of the challenge")
        }
    }
}

/// The last `count` days of one exercise against its daily target, oldest first, from the first
/// tracked day on.
private struct ExerciseDays {
    struct Day: Identifiable {
        let day: Date
        let total: Int
        let target: Int?
        var id: Date { day }
        var hit: Bool { target.map { total >= $0 } ?? false }
    }

    static func last(_ count: Int, of exercise: ExerciseInfo, in history: ChallengeHistory) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<count).reversed().compactMap { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            guard day >= history.firstTrackedDay else { return nil }
            return Day(day: day, total: history.total(of: exercise.id, on: day), target: history.target(of: exercise, on: day))
        }
    }
}

/// Bars per day, full colour when the target was hit, optionally with the target as a dashed line.
private struct ExerciseBars: View {
    let days: [ExerciseDays.Day]
    let unit: String
    var showsTarget = false

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value(unit, day.total))
                    .foregroundStyle(day.hit ? Palette.challenge : Palette.challenge.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if showsTarget {
                ForEach(days.filter { $0.target != nil }) { day in
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Target", day.target ?? 0))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One row per exercise: all-time total, the last 7 days and this week; tap for the details.
private struct ChallengeTotalsCard: View {
    let history: ChallengeHistory
    let exercises: [ExerciseInfo]

    var body: some View {
        Card(title: "Totals", systemImage: "sum", color: Palette.challenge) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 { Divider() }
                NavigationLink { ExerciseTotalsView(history: history, exercise: exercise) } label: { row(exercise) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func row(_ exercise: ExerciseInfo) -> some View {
        let week = history.total(of: exercise.id, in: history.week(containing: .now))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name).font(.subheadline.bold()).lineLimit(1)
                Text("\(week.formatted()) this week").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ExerciseBars(days: ExerciseDays.last(7, of: exercise, in: history), unit: exercise.unit.short)
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .frame(width: 70, height: 28)
            VStack(alignment: .trailing, spacing: 0) {
                Text(history.allTime(of: exercise.id).formatted()).numberFont(20)
                Text("all time").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name): \(history.allTime(of: exercise.id)) all time, \(week) this week")
        .accessibilityAddTraits(.isButton)
    }
}

/// One exercise: all-time total, the last 14 days against the daily target, and week / month / average.
private struct ExerciseTotalsView: View {
    let history: ChallengeHistory
    let exercise: ExerciseInfo

    private var calendar: Calendar { .current }

    var body: some View {
        let days = ExerciseDays.last(14, of: exercise, in: history)
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "Last 14 days", systemImage: "chart.bar.fill", color: Palette.challenge) {
                    ExerciseBars(days: days, unit: exercise.unit.short, showsTarget: true)
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                        .frame(height: 180)
                        .accessibilityLabel("\(exercise.name), last 14 days against the daily target")
                    Text("Full colour: target reached. Dashed line: the daily target.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    tile("All time", history.allTime(of: exercise.id))
                    tile("Week", history.total(of: exercise.id, in: history.week(containing: .now)))
                    tile("Month", history.total(of: exercise.id, in: calendar.dateInterval(of: .month, for: .now)!))
                    tile("Avg/day", history.averagePerDay(of: exercise.id, today: .now))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name)
    }

    private func tile(_ title: LocalizedStringResource, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .cardBackground(cornerRadius: 14)
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
