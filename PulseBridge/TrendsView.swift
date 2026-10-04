import PulseKit
import SwiftUI

extension Metric {
    var insightTopic: InsightTopic? {
        switch self {
        case .heartRate: .heartRate
        case .restingHeartRate: .restingHeartRate
        case .hrv: .hrv
        case .spo2: .spo2
        case .steps: .steps
        }
    }
}

extension InsightTopic {
    var title: String {
        switch self {
        case .sleep: "Time asleep"
        case .steps: Metric.steps.title
        case .restingHeartRate: Metric.restingHeartRate.title
        case .hrv: Metric.hrv.title
        case .heartRate: Metric.heartRate.title
        case .spo2: Metric.spo2.title
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .sleep: hoursAndMinutes(Int(value.rounded()))
        case .steps: Int(value.rounded()).formatted()
        case .restingHeartRate, .heartRate: "\(Int(value.rounded())) bpm"
        case .hrv: "\(Int(value.rounded())) ms"
        case .spo2: "\(Int(value.rounded()))%"
        }
    }

    /// "+25 min", "+12%", "-3 bpm"
    func change(_ comparison: WeekComparison) -> String {
        let sign = comparison.change >= 0 ? "+" : "-"
        switch self {
        case .sleep: return "\(sign)\(Int(abs(comparison.change).rounded())) min"
        case .steps:
            guard comparison.last > 0 else { return "-" }
            return "\(sign)\(Int((abs(comparison.change) / comparison.last * 100).rounded()))%"
        case .restingHeartRate, .heartRate: return "\(sign)\(Int(abs(comparison.change).rounded())) bpm"
        case .hrv: return "\(sign)\(Int(abs(comparison.change).rounded())) ms"
        case .spo2: return "\(sign)\(Int(abs(comparison.change).rounded()))%"
        }
    }

    /// Lower is better only for heart rate at rest.
    func direction(_ comparison: WeekComparison) -> InsightDirection {
        guard abs(comparison.change) > 0.5 else { return .neutral }
        let up = comparison.change > 0
        switch self {
        case .restingHeartRate, .heartRate: return up ? .worse : .better
        case .sleep, .steps, .hrv, .spo2: return up ? .better : .worse
        }
    }
}

/// The last 35 days as per-day values and insights, for Trends and the detail screens.
@MainActor
@Observable
final class TrendsModel {
    let service: SummaryService
    private(set) var series: [InsightTopic: [Date: Double]] = [:]
    private(set) var insights: [Insight] = []

    init(service: SummaryService) {
        self.service = service
    }

    func reload() {
        guard let metrics = try? service.load(days: SummaryModel.loadedDays, endingOn: .now) else { return }
        series = metrics.insightSeries()
        insights = Insights.make(series, today: .now, calendar: .current)
    }

    func comparison(_ topic: InsightTopic) -> WeekComparison? {
        Insights.week(series[topic] ?? [:], today: .now, calendar: .current, endingYesterday: topic == .steps)
    }

    /// The last 30 days, oldest first.
    func last30(_ topic: InsightTopic) -> [Double] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<30).reversed().compactMap { series[topic]?[Calendar.current.date(byAdding: .day, value: -$0, to: today)!] }
    }
}

/// Highlights, then each metric's week against the week before.
struct TrendsView: View {
    let service: SummaryService
    @State private var model: TrendsModel

    init(service: SummaryService) {
        self.service = service
        _model = State(initialValue: TrendsModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HighlightsCard(insights: model.insights, limit: 10)
                    SectionTitle("This week vs last week")
                    ForEach([InsightTopic.sleep, .steps, .restingHeartRate, .hrv, .heartRate, .spo2], id: \.self) { topic in
                        NavigationLink(value: topic.route) { row(topic) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Trends")
            .summaryDestinations(service: service)
            .task { model.reload() }
            .refreshable { model.reload() }
        }
    }

    private func row(_ topic: InsightTopic) -> some View {
        let comparison = model.comparison(topic)
        return Card(title: topic.title, systemImage: topic.systemImage, color: topic.color, chevron: true) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comparison.map { topic.format($0.this) } ?? "-").numberFont(26)
                    if let comparison {
                        Label("\(topic.change(comparison)) vs last week", systemImage: topic.direction(comparison).symbol)
                            .font(.caption.bold())
                            .foregroundStyle(topic.direction(comparison).color)
                    } else {
                        Text("Not enough data yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Sparkline(values: model.last30(topic), color: topic.color).frame(width: 120, height: 40)
            }
        }
    }
}

/// The one insight for a topic, if there is one, at the top of a detail screen.
struct TopicInsightRow: View {
    let service: SummaryService
    let topic: InsightTopic
    @State private var insight: Insight?

    var body: some View {
        Group {
            if let insight {
                Section {
                    Label {
                        Text(insight.text).font(.subheadline)
                    } icon: {
                        Image(systemName: insight.direction.symbol).foregroundStyle(insight.direction.color)
                    }
                }
            }
        }
        .task {
            let metrics = try? service.load(days: SummaryModel.loadedDays, endingOn: .now)
            insight = metrics.flatMap { m in Insights.make(m.insightSeries(), today: .now, calendar: .current).first { $0.topic == topic } }
        }
    }
}
