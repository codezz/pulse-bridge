import PulseKit
import SwiftUI

extension Metric {
    var insightTopic: InsightTopic? { InsightTopic.allCases.first { $0.metric == self } }
}

extension InsightTopic {
    var title: String { metric?.title ?? String(localized: "Time asleep") }

    func format(_ value: Double) -> String {
        switch self {
        case .sleep: hoursAndMinutes(Int(value.rounded()))
        case .steps: Int(value.rounded()).formatted()
        case .restingHeartRate, .heartRate: "\(Int(value.rounded())) bpm"
        case .hrv: "\(Int(value.rounded())) ms"
        case .spo2: "\(Int(value.rounded()))%"
        case .temperature: "\(Metric.temperature.format(value)) °C"
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
        case .temperature: return "\(Insights.signedCelsius(comparison.change)) °C"
        }
    }

    /// Same thresholds as the highlights: small changes get a neutral arrow.
    func direction(_ comparison: WeekComparison) -> InsightDirection { Insights.direction(self, comparison) }

    /// Totals and averages still changing today compare complete days only.
    var endsYesterday: Bool { self == .steps || self == .heartRate || self == .spo2 }
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
        Insights.week(series[topic] ?? [:], today: .now, calendar: .current, endingYesterday: topic.endsYesterday)
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
                    ForEach([InsightTopic.sleep, .steps, .restingHeartRate, .hrv, .temperature, .heartRate, .spo2], id: \.self) { topic in
                        NavigationLink(value: topic.route()) { row(topic) }
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

/// The insight for a detail screen's topic on its day, if there is one.
@MainActor
func topicInsight(_ topic: InsightTopic, service: SummaryService, day: Date) -> Insight? {
    guard let metrics = try? service.load(days: SummaryModel.loadedDays, endingOn: day) else { return nil }
    return Insights.make(metrics.insightSeries(), today: day, calendar: .current).first { $0.topic == topic }
}

/// The insight line at the top of a detail screen.
struct TopicInsightRow: View {
    let insight: Insight

    var body: some View {
        Section {
            Label {
                Text(insight.text).font(.subheadline)
            } icon: {
                Image(systemName: insight.direction.symbol).foregroundStyle(insight.direction.color)
            }
        }
    }
}
