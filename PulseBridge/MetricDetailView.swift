import Charts
import PulseKit
import SwiftUI

struct MetricDetailView: View {
    let metric: Metric
    let service: SummaryService

    init(metric: Metric, service: SummaryService, day: Date? = nil) {
        self.metric = metric
        self.service = service
        _day = State(initialValue: Calendar.current.startOfDay(for: day ?? .now))
    }
    @State private var range: DaySpan = .day
    @State private var day: Date
    @State private var metrics: DailyMetrics?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                DayRangeHeader(span: $range, day: $day, firstDay: metrics?.days.first)
            }
            Section {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(averageLabel).font(.caption).foregroundStyle(.secondary)
                        Text("\(metric.format(average)) \(metric.unit)").font(.title.bold())
                        if metric == .steps && range != .day && !series.isEmpty {
                            Text("Goal reached on \(series.filter { $0.range.average >= Double(stepGoal) }.count) of \(series.count) days")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    chart.frame(height: 240)
                }
            }
        }
        .navigationTitle(metric.title)
        .task(id: "\(range.rawValue)\(day.timeIntervalSince1970)") { load() }
    }

    private var series: [DailyValue] { metrics?.series(metric) ?? [] }

    /// HRV and resting HR are values of the night (D-1 18:00 to D 12:00), not of the calendar day.
    private var averageLabel: String {
        guard range == .day else { return "Daily average" }
        switch metric {
        case .hrv: return "Night average (asleep)"
        case .restingHeartRate: return "Night"
        case .heartRate, .spo2: return "Average"
        case .steps: return "Total"
        }
    }

    private var average: Double? {
        if range == .day { return metrics?.value(metric, on: day)?.average }
        guard !series.isEmpty else { return nil }
        return series.map(\.range.average).reduce(0, +) / Double(series.count)
    }

    @ViewBuilder private var chart: some View {
        if range == .day && metric == .steps {
            let hours = metrics?.readings(.steps, on: day) ?? []
            if hours.isEmpty { noData } else {
                Chart(hours, id: \.date) {
                    BarMark(x: .value("Hour", $0.date, unit: .hour), y: .value("Steps", $0.value))
                }
                .foregroundStyle(metric.color)
                .chartScrub(hours.map { .hour($0.date, "\(metric.format($0.value)) \(metric.unit)") })
            }
        } else if range == .day && metric != .restingHeartRate {
            let points = metrics?.readings(metric, on: day) ?? []
            if points.isEmpty { noData } else {
                Chart(points, id: \.date) {
                    PointMark(x: .value("Time", $0.date), y: .value(metric.unit, $0.value)).symbolSize(16)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .foregroundStyle(metric.color)
                .chartScrub(points.map { .time($0.date, "\(metric.format($0.value)) \(metric.unit)") })
            }
        } else if series.isEmpty {
            noData
        } else {
            Chart {
                ForEach(series) { value in
                    if metric == .heartRate || metric == .spo2 {
                        BarMark(x: .value("Day", value.day, unit: .day),
                                yStart: .value("Min", value.range.min), yEnd: .value("Max", value.range.max))
                            .opacity(0.35)
                        PointMark(x: .value("Day", value.day, unit: .day), y: .value("Average", value.range.average))
                    } else {
                        BarMark(x: .value("Day", value.day, unit: .day), y: .value(metric.unit, value.range.average))
                    }
                }
                if metric == .steps {
                    RuleMark(y: .value("Goal", stepGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2) }
                }
            }
            .chartYScale(domain: .automatic(includesZero: metric == .hrv || metric == .steps))
            .foregroundStyle(metric.color)
            .chartScrub(series.map { .day($0.day, scrubText($0)) })
        }
    }

    /// HR and SpO2 bars show the day's range; the rest one value per day.
    private func scrubText(_ value: DailyValue) -> String {
        switch metric {
        case .heartRate, .spo2:
            "\(metric.format(value.range.min))-\(metric.format(value.range.max)) \(metric.unit)"
        case .restingHeartRate, .hrv, .steps:
            "\(metric.format(value.range.average)) \(metric.unit)"
        }
    }

    private var noData: some View {
        Text("No data").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
    }

    private func load() {
        do {
            metrics = try service.load(days: range.days, endingOn: day)
            error = nil
        } catch {
            self.error = "Couldn't load data: \(error.localizedDescription)"
        }
    }
}
