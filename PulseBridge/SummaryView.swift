import Charts
import PulseKit
import SwiftUI

enum SummaryRoute: Hashable {
    /// `day`: open the detail on that day (default: today).
    case metric(Metric, day: Date? = nil)
    case sleep
    case activities
}

struct SummaryView: View {
    let coordinator: SyncCoordinator
    let model: SummaryModel
    let onShowBand: () -> Void
    @State private var showStart = false

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    private func metricLink(_ metric: Metric) -> some View {
        NavigationLink(value: SummaryRoute.metric(metric)) {
            MetricCard(metric: metric, metrics: model.metrics, today: today)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SummaryHeader(coordinator: coordinator, onTap: onShowBand)
                        .unredacted()
                    if let error = model.error {
                        Label("Couldn't load data: \(error)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    }
                    NavigationLink(value: SummaryRoute.sleep) {
                        SleepCard(metrics: model.metrics, today: today)
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: SummaryRoute.metric(.steps)) {
                        StepsCard(metrics: model.metrics, today: today, coordinator: coordinator)
                    }
                    .buttonStyle(.plain)
                    HeartRateCard(coordinator: coordinator, metrics: model.metrics, today: today)
                    ActivitiesCard(workouts: model.metrics?.workouts() ?? []) { showStart = true }
                    metricLink(.spo2)
                }
                .padding()
                .redacted(reason: model.isLoaded ? [] : .placeholder)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Summary")
            .navigationDestination(for: SummaryRoute.self) { route in
                switch route {
                case .metric(let metric, let day): MetricDetailView(metric: metric, service: model.service, day: day)
                case .sleep: SleepDetailView(service: model.service)
                case .activities: ActivitiesView(service: model.service)
                }
            }
            .refreshable { await coordinator.sync() }
            .sheet(isPresented: $showStart) {
                NavigationStack {
                    StartActivityForm(coordinator: coordinator) { showStart = false }
                }
                .presentationDetents([.medium, .large])
            }
        }
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

/// Today's steps toward the goal. Uses the band's live total while connected, else the last sync.
/// Reads the live total here so only this card redraws on each live update.
private struct StepsCard: View {
    let metrics: DailyMetrics?
    let today: Date
    let coordinator: SyncCoordinator

    private var live: LiveActivity? { coordinator.live.activity }

    private var steps: Int { max(live?.steps ?? 0, metrics?.stepsTotal(on: today) ?? 0) }
    private var meters: Int { max(live?.distanceMeters ?? 0, metrics?.distanceMeters(on: today) ?? 0) }

    var body: some View {
        Card(title: Metric.steps.title, systemImage: Metric.steps.systemImage, color: Metric.steps.color) {
            HStack(spacing: 16) {
                ProgressRing(progress: Double(steps) / Double(stepGoal), color: Metric.steps.color) {
                    Text("\(steps * 100 / stepGoal)%").font(.system(size: 15, weight: .bold, design: .rounded))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(steps.formatted()).numberFont(30)
                    Text("of \(stepGoal.formatted()) · \(roadDistanceText(Double(meters)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            let hours = metrics?.stepsByHour(on: today) ?? []
            if !hours.isEmpty {
                Chart(hours, id: \.date) {
                    BarMark(x: .value("Hour", $0.date, unit: .hour), y: .value("Steps", $0.value))
                }
                .foregroundStyle(Metric.steps.color)
                .frame(height: 60)
            }
        }
    }
}
