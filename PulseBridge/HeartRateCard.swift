import Charts
import PulseKit
import SwiftUI

/// Summary's heart-rate card: today's readings, or the last hour with the live line while live is
/// on, plus on-demand measurements. Reads live state itself so only this card redraws per beat.
struct HeartRateCard: View {
    let coordinator: SyncCoordinator
    let metrics: DailyMetrics?
    let today: Date

    private var live: Bool { coordinator.isLiveHeartRateOn }
    private var series: HeartRateSeries { coordinator.heartRate }
    private var connected: Bool { coordinator.band.state == .connected }
    private var readings: [Reading] { metrics?.readings(.heartRate, on: today) ?? [] }

    var body: some View {
        Card(title: Metric.heartRate.title, systemImage: Metric.heartRate.systemImage, color: Metric.heartRate.color) {
            NavigationLink(value: SummaryRoute.metric(.heartRate)) {
                VStack(alignment: .leading, spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        headline(now: context.date)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    chart
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            MeasureRow(coordinator: coordinator)
        } accessory: {
            liveButton
        }
        .sensoryFeedback(.impact, trigger: live)
    }

    private var liveButton: some View {
        Button {
            live ? coordinator.stopLiveHeartRate() : coordinator.startLiveHeartRate()
        } label: {
            if live {
                Label("Live", systemImage: "stop.fill")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.red, in: Capsule())
            } else {
                Label("Live", systemImage: "heart.fill").font(.caption.bold())
            }
        }
        .buttonStyle(.borderless)
        .disabled(!live && !connected)
        .accessibilityLabel(live ? "Stop live heart rate" : "Start live heart rate")
    }

    @ViewBuilder private func headline(now: Date) -> some View {
        let bpm = live ? series.latest : readings.last.map { Int($0.value) }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(bpm.map(String.init) ?? "-").numberFont(40).contentTransition(.numericText())
            Text("bpm").foregroundStyle(.secondary)
            if live { BeatingHeart(bpm: series.isStale(now: now) ? nil : series.latest) }
            Spacer()
            if live, let bpm {
                let zone = coordinator.heartRateProfile().zones.zone(for: bpm)
                Text("Zone \(zone) · \(zoneName(zone))").font(.caption.bold()).foregroundStyle(zoneColor(zone))
            }
        }
        if live, let status = status(now: now) {
            Label(status.text, systemImage: status.icon).font(.caption).foregroundStyle(status.color)
        }
    }

    private func status(now: Date) -> (text: String, icon: String, color: Color)? {
        if !connected { return ("Not connected", "antenna.radiowaves.left.and.right.slash", .secondary) }
        if series.samples.isEmpty { return ("Starting the sensor...", "hourglass", .secondary) }
        if series.isStale(now: now) { return ("Not on wrist?", "hand.raised", .orange) }
        return nil
    }

    /// "today 54-118 · resting 58"
    private var subtitle: String {
        var parts: [String] = []
        if let range = metrics?.value(.heartRate, on: today) { parts.append("today \(Int(range.min))-\(Int(range.max))") }
        if let resting = metrics?.restingHeartRate(on: today) { parts.append("resting \(resting)") }
        return parts.isEmpty ? "No data today" : parts.joined(separator: " · ")
    }

    @ViewBuilder private var chart: some View {
        let domain = HeartRateChartRange.domain(live: live, now: .now, calendar: .current)
        let stored = readings.filter { domain.contains($0.date) }
        let runs = live ? series.zoneRuns(coordinator.heartRateProfile().zones) : []
        if !stored.isEmpty || !runs.isEmpty {
            Chart {
                ForEach(stored, id: \.date) {
                    PointMark(x: .value("Time", $0.date), y: .value("bpm", $0.value))
                        .symbolSize(12)
                        .foregroundStyle(Metric.heartRate.color.opacity(live ? 0.4 : 1))
                }
                ForEach(runs) { run in
                    ForEach(run.samples) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("bpm", sample.bpm),
                                 series: .value("Run", run.id))
                            .foregroundStyle(zoneColor(run.zone))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 100)
            .animation(.easeInOut(duration: 0.4), value: live)
        }
    }
}

/// A heart that beats at `bpm`; still when there's no reading or Reduce Motion is on.
private struct BeatingHeart: View {
    let bpm: Int?
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "heart.fill")
            .foregroundStyle(.red)
            .scaleEffect(beat ? 1.25 : 1)
            .accessibilityHidden(true)
            .task(id: reduceMotion ? nil : bpm) {
                guard let bpm, bpm > 0, !reduceMotion else { beat = false; return }
                let period = max(0.3, 60 / Double(bpm))
                while !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.1)) { beat = true }
                    try? await Task.sleep(for: .seconds(0.1))
                    withAnimation(.easeIn(duration: 0.25)) { beat = false }
                    try? await Task.sleep(for: .seconds(period - 0.1))
                }
            }
    }
}

/// HRV and 30 s heart-rate measurements, compact: buttons, then progress, then the result.
struct MeasureRow: View {
    let coordinator: SyncCoordinator
    private var live: LiveFeed { coordinator.live }

    var body: some View {
        Group {
            switch live.measurement {
            case .idle:
                HStack {
                    button("HRV", "75 s", .hrv)
                    button("Heart rate", "30 s", .heartRate)
                }
                .disabled(coordinator.band.state != .connected || coordinator.phase.isBusy || coordinator.activity != nil)
            case let .running(kind, latest, startedAt):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let progress = min(1, context.date.timeIntervalSince(startedAt) / kind.expectedDuration)
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress) { Text("Measuring \(kind.title)... keep still").font(.subheadline) }
                        HStack {
                            Text("HR \(latest.map { $0.heartRate > 0 ? "\($0.heartRate) bpm" : "-" } ?? "-")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Cancel", role: .cancel) { Task { await live.cancelMeasurement() } }.font(.caption)
                        }
                    }
                }
            case let .finished(values):
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Heart rate", value: "\(values.heartRate) bpm")
                    if values.kind == .hrv {
                        LabeledContent("HRV", value: "\(values.hrv) ms")
                        LabeledContent("Stress", value: "\(values.stress)")
                        LabeledContent("Blood pressure (estimate)", value: "\(values.systolic)/\(values.diastolic)")
                        Text("Saved on the band; it reaches Apple Health on the next sync.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Done") { live.resetMeasurement() }
                }
                .font(.subheadline)
            case .failed, .interrupted:
                HStack {
                    Text(live.measurement.problem).font(.subheadline).foregroundStyle(.orange)
                    Spacer()
                    Button("OK") { live.resetMeasurement() }
                }
            }
        }
        .sensoryFeedback(trigger: live.measurement) { _, new in
            switch new {
            case .finished: .success
            case .failed, .interrupted: .error
            default: nil
            }
        }
    }

    private func button(_ title: String, _ duration: String, _ kind: MeasurementKind) -> some View {
        Button {
            Task { await coordinator.measure(kind) }
        } label: {
            VStack {
                Text(title).bold()
                Text(duration).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
