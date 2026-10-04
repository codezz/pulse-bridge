import PulseKit
import SwiftUI

/// Ring values for one day: sleep score, steps and challenge progress (0...1, more for a second lap).
struct DayRings {
    var sleep: Double
    var steps: Double
    var challenge: Double?

    @MainActor
    static func of(_ day: Date, metrics: DailyMetrics?, challenge: ChallengeModel, liveSteps: Int? = nil) -> DayRings {
        let sleep = Double(metrics?.sleepScore(on: day)?.value ?? 0) / 100
        let steps = Double(max(liveSteps ?? 0, metrics?.stepsTotal(on: day) ?? 0)) / Double(stepGoal)
        let active = challenge.history.exercises.filter { challenge.history.isActive($0, on: day) }
        let progress = active.map { min(1, challenge.history.progress(of: $0, on: day).fraction) }
        return DayRings(sleep: sleep, steps: steps,
                        challenge: progress.isEmpty ? nil : progress.reduce(0, +) / Double(progress.count))
    }

    var rings: [ActivityRings.Ring] {
        var result = [ActivityRings.Ring(id: "Sleep", progress: sleep, color: Palette.sleep),
                      ActivityRings.Ring(id: "Steps", progress: steps, color: Palette.steps)]
        if let challenge { result.append(ActivityRings.Ring(id: "Challenge", progress: challenge, color: Palette.challenge)) }
        return result
    }
}

/// The selected day's week (Monday first) with tiny rings per day.
struct DayStrip: View {
    @Binding var selected: Date
    let rings: (Date) -> DayRings

    private static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    static func weekStart(of day: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)!.start
    }

    private var days: [Date] {
        let start = Self.weekStart(of: selected)
        return (0..<7).map { Self.calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private var today: Date { Self.calendar.startOfDay(for: .now) }

    var body: some View {
        HStack(spacing: 4) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous week")
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
                .disabled(days.contains(today))
                .accessibilityLabel("Next week")
        }
        .buttonStyle(.borderless)
        .font(.caption.bold())
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = Self.calendar.isDate(day, inSameDayAs: selected)
        let future = day > today
        return Button { selected = day } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.narrow))).foregroundStyle(.secondary)
                ActivityRings(rings: future ? [] : rings(day).rings, size: 30)
                    .opacity(future ? 0.2 : 1)
                Text("\(Self.calendar.component(.day, from: day))")
                    .foregroundStyle(Self.calendar.isDateInToday(day) ? Color.accentColor : .primary)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color(.tertiarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .disabled(future)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shift(_ days: Int) {
        let moved = Self.calendar.date(byAdding: .day, value: days, to: selected)!
        selected = min(moved, today)
    }
}

/// Rings for the day with one line per ring, and a celebration when a goal is reached.
struct TodayHero: View {
    let day: Date
    let metrics: DailyMetrics?
    let challenge: ChallengeModel
    let liveSteps: Int?
    let isToday: Bool

    var body: some View {
        let values = DayRings.of(day, metrics: metrics, challenge: challenge, liveSteps: isToday ? liveSteps : nil)
        HStack(spacing: 20) {
            ActivityRings(rings: values.rings, size: 118)
            VStack(alignment: .leading, spacing: 10) {
                row("Sleep", Palette.sleep, sleepText)
                row("Steps", Palette.steps, "\(Int(values.steps * Double(stepGoal)).formatted()) / \(stepGoal.formatted())")
                if values.challenge != nil {
                    row("Challenge", Palette.challenge, challengeText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .celebrates(isToday && values.steps >= 1)
        .celebrates(isToday && challenge.history.status(on: day) == .done)
    }

    private func row(_ title: String, _ color: Color, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.bold()).foregroundStyle(color)
            Text(value).font(.headline).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var sleepText: String {
        guard let night = metrics?.sleep(on: day), let score = metrics?.sleepScore(on: day) else { return "-" }
        return "\(score.value) · \(hoursAndMinutes(night.asleep))"
    }

    private var challengeText: String {
        challenge.exercises.filter { challenge.history.isActive($0, on: day) }
            .map { let p = challenge.history.progress(of: $0, on: day); return "\(p.total)/\(p.target)" }
            .joined(separator: " · ")
    }
}

extension InsightTopic {
    var systemImage: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .steps: Metric.steps.systemImage
        case .restingHeartRate: Metric.restingHeartRate.systemImage
        case .hrv: Metric.hrv.systemImage
        case .heartRate: Metric.heartRate.systemImage
        case .spo2: Metric.spo2.systemImage
        }
    }

    var color: Color {
        switch self {
        case .sleep: Palette.sleep
        case .steps: Metric.steps.color
        case .restingHeartRate: Metric.restingHeartRate.color
        case .hrv: Metric.hrv.color
        case .heartRate: Metric.heartRate.color
        case .spo2: Metric.spo2.color
        }
    }

    var route: SummaryRoute {
        switch self {
        case .sleep: .sleep
        case .steps: .metric(.steps)
        case .restingHeartRate: .metric(.restingHeartRate)
        case .hrv: .metric(.hrv)
        case .heartRate: .metric(.heartRate)
        case .spo2: .metric(.spo2)
        }
    }
}

extension InsightDirection {
    var symbol: String {
        switch self {
        case .better: "arrow.up.right.circle.fill"
        case .worse: "arrow.down.right.circle.fill"
        case .neutral: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .better: .green
        case .worse: .orange
        case .neutral: .secondary
        }
    }
}

/// Up to `limit` insight lines; each opens its metric.
struct HighlightsCard: View {
    let insights: [Insight]
    var limit = 3

    var body: some View {
        Card(title: "Highlights", systemImage: "sparkles", color: .yellow) {
            if insights.isEmpty {
                Text("Nothing stands out yet. Highlights appear once there are a few nights and days to compare.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(insights.prefix(limit)) { insight in
                NavigationLink(value: insight.topic.route) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.topic.systemImage).foregroundStyle(insight.topic.color).frame(width: 22)
                        Text(insight.text).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: insight.direction.symbol).foregroundStyle(insight.direction.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Resting HR, HRV, blood oxygen and steps as tiles. Reads the live step count itself, so only this
/// grid redraws on live updates.
struct VitalsGrid: View {
    let day: Date
    let metrics: DailyMetrics?
    let coordinator: SyncCoordinator
    let isToday: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            tile(.restingHeartRate, value: metrics?.restingHeartRate(on: day).map(String.init), caption: "Last night",
                 sparkline: nightly(.restingHeartRate))
            tile(.hrv, value: metrics?.hrv(on: day).map(String.init), caption: "Last night", sparkline: nightly(.hrv))
            tile(.spo2, value: metrics?.readings(.spo2, on: day).last.map { Metric.spo2.format($0.value) },
                 caption: metrics?.readings(.spo2, on: day).last.map { $0.date.formatted(date: .omitted, time: .shortened) },
                 sparkline: (metrics?.readings(.spo2, on: day) ?? []).map(\.value))
            tile(.steps, value: steps.formatted(), caption: "of \(stepGoal.formatted())",
                 sparkline: (metrics?.stepsByHour(on: day) ?? []).map(\.value))
        }
    }

    private var steps: Int {
        let live = isToday ? coordinator.live.activity?.steps ?? 0 : 0
        return max(live, metrics?.stepsTotal(on: day) ?? 0)
    }

    /// The 14 nights up to the selected day.
    private func nightly(_ metric: Metric) -> [Double] {
        (metrics?.series(metric) ?? []).filter { $0.day <= day }.suffix(14).map(\.range.average)
    }

    private func tile(_ metric: Metric, value: String?, caption: String?, sparkline: [Double]) -> some View {
        NavigationLink(value: SummaryRoute.metric(metric, day: day)) {
            MetricTile(title: metric.title, systemImage: metric.systemImage, color: metric.color, value: value ?? "-",
                       unit: metric.unit, caption: value == nil ? "No data" : caption, sparkline: sparkline)
        }
        .buttonStyle(.plain)
    }
}

/// Sections below the hero, in the user's order; hidden ones are skipped.
enum TodaySection: String, CaseIterable, Identifiable {
    case highlights, sleep, heartRate, vitals, challenge, activities
    var id: String { rawValue }

    var title: String {
        switch self {
        case .highlights: "Highlights"
        case .sleep: "Sleep"
        case .heartRate: "Heart rate"
        case .vitals: "Vitals"
        case .challenge: "Daily challenge"
        case .activities: "Activities"
        }
    }
}

/// The Today layout, saved on this device. Unknown stored ids are dropped; new sections go last.
@MainActor
@Observable
final class TodayLayout {
    private static let orderKey = "todayOrder", hiddenKey = "todayHidden"

    private(set) var order: [TodaySection]
    private(set) var hidden: Set<TodaySection>

    init() {
        let stored = (UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []).compactMap(TodaySection.init(rawValue:))
        order = stored + TodaySection.allCases.filter { !stored.contains($0) }
        hidden = Set((UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []).compactMap(TodaySection.init(rawValue:)))
    }

    var visible: [TodaySection] { order.filter { !hidden.contains($0) } }

    func move(from: IndexSet, to: Int) {
        order.move(fromOffsets: from, toOffset: to)
        save()
    }

    func setVisible(_ section: TodaySection, _ visible: Bool) {
        if visible { hidden.remove(section) } else { hidden.insert(section) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: Self.orderKey)
        UserDefaults.standard.set(hidden.map(\.rawValue), forKey: Self.hiddenKey)
    }
}

struct EditTodayView: View {
    let layout: TodayLayout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order) { section in
                        Toggle(section.title, isOn: Binding(get: { !layout.hidden.contains(section) },
                                                            set: { layout.setVisible(section, $0) }))
                    }
                    .onMove { layout.move(from: $0, to: $1) }
                } footer: {
                    Text("Drag to reorder, switch off what you don't need. The rings and the day strip always stay on top.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
