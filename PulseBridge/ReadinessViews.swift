import Charts
import PulseKit
import SwiftUI

extension ReadinessContributor.Kind {
    var title: String {
        switch self {
        case .hrv: "HRV balance"
        case .restingHeartRate: "Resting heart rate"
        case .sleep: "Sleep"
        case .activity: "Activity balance"
        case .temperature: "Body temperature"
        }
    }

    var systemImage: String {
        switch self {
        case .hrv: Metric.hrv.systemImage
        case .restingHeartRate: Metric.restingHeartRate.systemImage
        case .sleep: "moon.zzz.fill"
        case .activity: "figure.walk"
        case .temperature: Metric.temperature.systemImage
        }
    }
}

/// Today's readiness: score ring, label, the main reason and the contributors.
struct ReadinessCard: View {
    let result: ReadinessResult?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Card(title: "Readiness", systemImage: "bolt.heart.fill", color: .teal, chevron: true) {
                switch result {
                case .score(let score):
                    HStack(spacing: 16) {
                        ScoreRing(score: score.value)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(score.label).font(.title3.bold()).foregroundStyle(scoreColor(score.value))
                            Text(score.reason).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    ContributorBars(contributors: score.contributors, compact: true)
                case .calibrating(let nights):
                    Text(nights > 0
                         ? "Calibrating: \(nights) more \(nights == 1 ? "night" : "nights") with the band to learn your baseline."
                         : "No HRV or resting heart rate from last night yet. Sync after waking up.")
                        .font(.subheadline).foregroundStyle(.secondary)
                case nil:
                    Text("-").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// One bar per contributor (0-100) with its value.
struct ContributorBars: View {
    let contributors: [ReadinessContributor]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            ForEach(contributors) { contributor in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label(contributor.kind.title, systemImage: contributor.kind.systemImage).font(compact ? .caption : .subheadline)
                        Spacer()
                        Text(compact ? "\(contributor.score)" : contributor.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(contributor.score), total: 100).tint(scoreColor(contributor.score))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Contributors in full and the last 14 days.
struct ReadinessDetailView: View {
    let model: SummaryModel
    @Environment(\.dismiss) private var dismiss

    private struct DayScore: Identifiable {
        let day: Date
        let value: Int
        var id: Date { day }
    }

    private var lastDays: [DayScore] {
        (0..<14).reversed().compactMap { back in
            let day = Calendar.current.date(byAdding: .day, value: -back, to: model.selectedDay)!
            guard case .score(let score) = model.readiness(on: day) else { return nil }
            return DayScore(day: day, value: score.value)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if case .score(let score) = model.readiness {
                    Section {
                        HStack(spacing: 16) {
                            ScoreRing(score: score.value, size: 80)
                            VStack(alignment: .leading) {
                                Text(score.label).font(.title2.bold()).foregroundStyle(scoreColor(score.value))
                                Text(score.reason).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Contributors") { ContributorBars(contributors: score.contributors) }
                }
                if lastDays.count > 1 {
                    Section("Last 14 days") {
                        Chart(lastDays) {
                            BarMark(x: .value("Day", $0.day, unit: .day), y: .value("Readiness", $0.value))
                                .foregroundStyle(scoreColor($0.value))
                        }
                        .chartYScale(domain: 0...100)
                        .chartScrub(lastDays.map { .day($0.day, "\($0.value)") })
                        .frame(height: 160)
                    }
                }
                Section {
                    Text("Readiness compares last night with your own baseline (average of up to 30 earlier nights): HRV 35%, resting heart rate 25%, sleep score 20%, yesterday's steps against your usual 10%, and night temperature 10% (warmer than usual lowers it). It needs 5 earlier nights to start.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
