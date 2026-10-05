import Charts
import PulseKit
import SwiftUI

enum SummaryRoute: Hashable {
    /// `day`: open the detail on that day (default: today).
    case metric(Metric, day: Date? = nil)
    case sleep(day: Date? = nil)
    case activities
}

extension View {
    /// Detail screens reachable from Today and Trends.
    func summaryDestinations(service: SummaryService) -> some View {
        navigationDestination(for: SummaryRoute.self) { route in
            switch route {
            case .metric(let metric, let day): MetricDetailView(metric: metric, service: service, day: day)
            case .sleep(let day): SleepDetailView(service: service, day: day)
            case .activities: ActivitiesView(service: service)
            }
        }
    }
}

struct SummaryView: View {
    let coordinator: SyncCoordinator
    let model: SummaryModel
    let onShowBand: () -> Void
    let onShowChallenge: () -> Void
    @State private var showStart = false
    @State private var showEdit = false
    @State private var showReadiness = false
    private let layout = TodayLayout.shared

    private var day: Date { model.selectedDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryHeader(coordinator: coordinator, onTap: onShowBand)
                        .unredacted()
                    DayStrip(selected: Binding(get: { model.selectedDay }, set: { model.select($0) }),
                             rings: { DayRings.of($0, metrics: model.metrics, challenge: coordinator.challenge, liveSteps: $1) },
                             liveSteps: { coordinator.live.activity?.steps })
                        .unredacted()
                    if let error = model.error {
                        Label("Couldn't load data: \(error)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    TodayHero(day: day, metrics: model.metrics, coordinator: coordinator, isToday: model.isToday,
                              isLoaded: model.isLoaded)
                    ForEach(layout.visible) { section in
                        sectionView(section)
                    }
                    Button("Edit Today", systemImage: "slider.horizontal.3") { showEdit = true }
                        .font(.subheadline)
                        .padding(.top, 4)
                }
                .padding()
                .redacted(reason: model.isLoaded ? [] : .placeholder)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month()))
            .toolbar {
                if !model.isToday {
                    Button("Today") { model.select(.now) }
                }
            }
            .summaryDestinations(service: model.service)
            .refreshable { await coordinator.sync() }
            .sheet(isPresented: $showStart) {
                NavigationStack {
                    StartActivityForm(coordinator: coordinator) { showStart = false }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showEdit) { EditTodayView(layout: layout) }
            .sheet(isPresented: $showReadiness) { ReadinessDetailView(model: model) }
        }
    }

    @ViewBuilder private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .readiness:
            ReadinessCard(result: model.readiness, isToday: model.isToday) { showReadiness = true }
        case .highlights:
            HighlightsCard(insights: model.insights, day: model.isToday ? nil : day)
        case .sleep:
            NavigationLink(value: SummaryRoute.sleep(day: day)) {
                SleepCard(metrics: model.metrics, today: day)
            }
            .buttonStyle(.plain)
        case .heartRate:
            if model.isToday {
                HeartRateCard(coordinator: coordinator, readings: model.metrics?.readings(.heartRate, on: day) ?? [],
                              subtitle: HeartRateCard.subtitle(metrics: model.metrics, today: day))
            } else {
                // Past days: the stored readings only (no live heart rate, no measurements).
                NavigationLink(value: SummaryRoute.metric(.heartRate, day: day)) {
                    HeartRateDayCard(metrics: model.metrics, day: day)
                }
                .buttonStyle(.plain)
            }
        case .vitals:
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Vitals")
                VitalsGrid(day: day, metrics: model.metrics, coordinator: coordinator, isToday: model.isToday)
            }
        case .challenge:
            ChallengeCard(model: coordinator.challenge, day: day, onOpen: onShowChallenge)
        case .activities:
            ActivitiesCard(workouts: recentWorkouts) { showStart = true }
        }
    }

    /// The 7 days up to the selected day.
    private var recentWorkouts: [Workout] {
        let from = Calendar.current.date(byAdding: .day, value: -6, to: day)!
        let to = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        return (model.metrics?.workouts() ?? []).filter { $0.start >= from && $0.start < to }
    }
}

/// Heart rate on a past day: the day's stored readings (live heart rate is for today only).
private struct HeartRateDayCard: View {
    let metrics: DailyMetrics?
    let day: Date

    private var readings: [Reading] { metrics?.readings(.heartRate, on: day) ?? [] }

    var body: some View {
        let metric = Metric.heartRate
        Card(title: metric.title, systemImage: metric.systemImage, color: metric.color, chevron: true) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.format(readings.last?.value)).numberFont(40)
                Text(metric.unit).foregroundStyle(.secondary)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            if !readings.isEmpty {
                Chart(readings, id: \.date) {
                    PointMark(x: .value("Time", $0.date), y: .value(metric.unit, $0.value)).symbolSize(12)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .foregroundStyle(metric.color)
                .frame(height: 80)
            }
        }
    }

    private var caption: String {
        guard let range = metrics?.value(.heartRate, on: day), let last = readings.last else { return "No data" }
        return "\(last.date.formatted(date: .omitted, time: .shortened)) · \(Int(range.min))-\(Int(range.max))"
    }
}

private struct SleepCard: View {
    let metrics: DailyMetrics?
    let today: Date

    private var night: SleepNight? { metrics?.sleep(on: today) }

    var body: some View {
        Card(title: "Sleep", systemImage: "moon.zzz.fill", color: Palette.sleep, chevron: true) {
            if let night, let metrics, let score = metrics.sleepScore(on: today) {
                HStack(spacing: 16) {
                    ScoreRing(score: score.value)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hoursAndMinutes(night.asleep)).numberFont(30)
                        Text("\(night.fellAsleep.formatted(date: .omitted, time: .shortened)) - \(night.wokeUp.formatted(date: .omitted, time: .shortened)) · \(score.label)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                StageBar(night: night)
                HStack {
                    vital("Resting HR", metrics.restingHeartRate(on: today).map { "\($0) bpm" })
                    vital("HRV", metrics.hrv(on: today).map { "\($0) ms" })
                }
            } else {
                Text(Calendar.current.isDateInToday(today) ? "No sleep data for last night" : "No sleep data for this night")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func vital(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading) {
            Text(value ?? "-").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
