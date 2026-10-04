import Charts
import PulseKit
import SwiftUI

enum SummaryRoute: Hashable {
    /// `day`: open the detail on that day (default: today).
    case metric(Metric, day: Date? = nil)
    case sleep
    case activities
}

extension View {
    /// Detail screens reachable from Today and Trends.
    func summaryDestinations(service: SummaryService) -> some View {
        navigationDestination(for: SummaryRoute.self) { route in
            switch route {
            case .metric(let metric, let day): MetricDetailView(metric: metric, service: service, day: day)
            case .sleep: SleepDetailView(service: service)
            case .activities: ActivitiesView(service: service)
            }
        }
    }
}

struct SummaryView: View {
    let coordinator: SyncCoordinator
    @Bindable var model: SummaryModel
    let onShowBand: () -> Void
    let onShowChallenge: () -> Void
    @State private var showStart = false
    @State private var showEdit = false
    @State private var layout = TodayLayout()

    private var day: Date { model.selectedDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryHeader(coordinator: coordinator, onTap: onShowBand)
                        .unredacted()
                    DayStrip(selected: $model.selectedDay) { DayRings.of($0, metrics: model.metrics, challenge: coordinator.challenge) }
                        .unredacted()
                    if let error = model.error {
                        Label("Couldn't load data: \(error)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    TodayHero(day: day, metrics: model.metrics, challenge: coordinator.challenge,
                              liveSteps: coordinator.live.activity?.steps, isToday: model.isToday)
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
                    Button("Today") { model.selectedDay = Calendar.current.startOfDay(for: .now) }
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
        }
    }

    @ViewBuilder private func sectionView(_ section: TodaySection) -> some View {
        switch section {
        case .highlights:
            HighlightsCard(insights: model.insights)
        case .sleep:
            NavigationLink(value: SummaryRoute.sleep) {
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
                    MetricCard(metric: .heartRate, metrics: model.metrics, today: day)
                }
                .buttonStyle(.plain)
            }
        case .vitals:
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Vitals")
                VitalsGrid(day: day, metrics: model.metrics, coordinator: coordinator, isToday: model.isToday)
            }
        case .challenge:
            ChallengeCard(model: coordinator.challenge, day: day, onLog: onShowChallenge, onOpen: onShowChallenge)
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

private struct MetricCard: View {
    let metric: Metric
    let metrics: DailyMetrics?
    let today: Date

    var body: some View {
        Card(title: metric.title, systemImage: metric.systemImage, color: metric.color) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline).numberFont(40)
                Text(metric.unit).foregroundStyle(.secondary)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            if hasChartData { chart.frame(height: 80) }
        }
    }

    private var todayReadings: [Reading] { metrics?.readings(metric, on: today) ?? [] }

    /// Empty cards stay compact instead of showing blank axes.
    private var hasChartData: Bool {
        switch metric {
        case .heartRate, .spo2: !todayReadings.isEmpty
        case .restingHeartRate, .hrv, .steps: !(metrics?.series(metric).isEmpty ?? true)
        }
    }

    /// Latest reading for HR and SpO2, last night's value for resting HR and HRV.
    private var headline: String {
        switch metric {
        case .heartRate, .spo2: metric.format(todayReadings.last?.value)
        case .restingHeartRate, .hrv, .steps: metric.format(metrics?.value(metric, on: today)?.average)
        }
    }

    private var caption: String {
        switch metric {
        case .heartRate, .spo2:
            guard let range = metrics?.value(metric, on: today), let last = todayReadings.last else { return "No data today" }
            return "\(last.date.formatted(date: .omitted, time: .shortened)) · today \(Int(range.min))-\(Int(range.max))"
        case .restingHeartRate, .hrv, .steps:
            return metrics?.value(metric, on: today) == nil ? "No data last night" : "Last night"
        }
    }

    @ViewBuilder private var chart: some View {
        switch metric {
        case .heartRate, .spo2:
            Chart(todayReadings, id: \.date) {
                PointMark(x: .value("Time", $0.date), y: .value(metric.unit, $0.value)).symbolSize(12)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .foregroundStyle(metric.color)
        case .restingHeartRate, .hrv, .steps:
            Chart(metrics?.series(metric) ?? []) {
                BarMark(x: .value("Day", $0.day, unit: .day), y: .value(metric.unit, $0.range.average))
            }
            .foregroundStyle(metric.color)
        }
    }
}

private struct SleepCard: View {
    let metrics: DailyMetrics?
    let today: Date

    private var night: SleepNight? { metrics?.sleep(on: today) }

    var body: some View {
        Card(title: "Sleep", systemImage: "moon.zzz.fill", color: .indigo) {
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
                Text("No sleep data for last night").foregroundStyle(.secondary)
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
