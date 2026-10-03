import Charts
import PulseBLE
import PulseKit
import SwiftUI

/// The Band tab: connection, sync and Apple Health export. Data lives in Summary.
struct BandView: View {
    let coordinator: SyncCoordinator
    let onPair: () -> Void
    @State private var confirmForget = false

    private var band: BandClient { coordinator.band }

    private var profileSummary: String {
        guard let p = coordinator.profile else { return "Set your age for accurate heart-rate zones" }
        return "\(p.age(at: .now, calendar: .current)) years · \(p.sex == .male ? "male" : "female") · \(p.heightCm) cm · \(p.weightKg) kg"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BandCard(coordinator: coordinator, onPair: onPair)
                    NavigationLink {
                        ProfileView(coordinator: coordinator)
                    } label: {
                        Card(title: "Profile and zones", systemImage: "person.crop.circle", color: .blue) {
                            Text(profileSummary).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    DiagnosticsCard(log: coordinator.diagnostics)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Band")
            .toolbar {
                Menu {
                    Button("Forget band", role: .destructive) { confirmForget = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("Forget this band? You'll need to pair it again. Data on the phone stays.", isPresented: $confirmForget,
                                titleVisibility: .visible) {
                Button("Forget band", role: .destructive) {
                    band.forget()
                    onPair()
                }
            }
        }
    }
}

/// Export or clear the diagnostics log, for bug reports.
private struct DiagnosticsCard: View {
    let log: DiagnosticsLog
    @State private var size = 0
    @State private var confirmClear = false

    var body: some View {
        Card(title: "Diagnostics", systemImage: "doc.text.magnifyingglass", color: .gray) {
            Text("Band traffic and sync events from recent syncs (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))). Useful when reporting a problem. It contains your raw band data, so share it only with people you trust.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ShareLink(item: log.url, subject: Text("Pulse Bridge diagnostics")) {
                    Label("Export log", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Clear", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog("Clear the diagnostics log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                log.clear()
                refresh()
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        size = (try? FileManager.default.attributesOfItem(atPath: log.url.path)[.size] as? Int) ?? 0
    }
}

/// Live heart rate on demand, for Summary: a Start button, then the live chart until Stop.
struct LiveHeartRateCard: View {
    let coordinator: SyncCoordinator
    @State private var running = false

    var body: some View {
        if running {
            HeartRateCard(coordinator: coordinator, onStop: {
                coordinator.stopLiveHeartRate()
                running = false
            })
        } else {
            Card(title: "Live heart rate", systemImage: "heart.fill", color: .red) {
                Button {
                    coordinator.startLiveHeartRate()
                    running = true
                } label: {
                    Label("Start live heart rate", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.band.state != .connected)
            }
        }
    }
}

/// Health-style colored badge with a white symbol.
struct IconBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Shared card chrome.
struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    var color: Color = .gray
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemImage: systemImage, color: color)
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HeartRateCard: View {
    /// Reads the series here, so only this card redraws on every heart-rate notification.
    let coordinator: SyncCoordinator
    let onStop: () -> Void
    private var series: HeartRateSeries { coordinator.heartRate }
    private var connected: Bool { coordinator.band.state == .connected }

    var body: some View {
        Card(title: "Live heart rate", systemImage: "heart.fill", color: .red) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text(series.latest.map(String.init) ?? "-")
                        .numberFont(56)
                        .contentTransition(.numericText())
                    Text("bpm").foregroundStyle(.secondary)
                    Spacer()
                    if !connected {
                        Text("Not connected").foregroundStyle(.secondary)
                    } else if series.samples.isEmpty {
                        Text("Starting the sensor...").foregroundStyle(.secondary)
                    } else if series.isStale(now: context.date) {
                        Label("Not on wrist?", systemImage: "hand.raised").foregroundStyle(.orange)
                    }
                }
            }
            Chart(series.samples) { sample in
                LineMark(x: .value("Time", sample.date), y: .value("BPM", sample.bpm),
                         series: .value("Segment", sample.segment))
                    .foregroundStyle(.red)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 140)
            HStack {
                stat("Min", series.minimum)
                stat("Avg", series.average)
                stat("Max", series.maximum)
            }
            Button("Stop", role: .cancel, action: onStop)
        }
    }

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack {
            Text(value.map(String.init) ?? "-").font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MeasureCard: View {
    let coordinator: SyncCoordinator
    private var live: LiveFeed { coordinator.live }

    var body: some View {
        Card(title: "Measure now", systemImage: "waveform.path.ecg", color: .purple) {
            switch live.measurement {
            case .idle:
                HStack {
                    button("HRV", "75 s", .hrv)
                    button("Heart rate", "30 s", .heartRate)
                }
                .disabled(coordinator.band.state != .connected || coordinator.phase.isBusy)
            case let .running(kind, latest, startedAt):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let progress = min(1, context.date.timeIntervalSince(startedAt) / kind.expectedDuration)
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: progress) { Text("Measuring \(kind.title)... keep still") }
                        Text("HR \(latest.map { $0.heartRate > 0 ? "\($0.heartRate) bpm" : "-" } ?? "-")")
                            .foregroundStyle(.secondary)
                        Button("Cancel", role: .cancel) { Task { await live.cancelMeasurement() } }
                    }
                }
            case let .finished(values):
                VStack(alignment: .leading, spacing: 6) {
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
            case .failed, .interrupted:
                VStack(alignment: .leading, spacing: 6) {
                    Text(live.measurement.problem).foregroundStyle(.orange)
                    Button("OK") { live.resetMeasurement() }
                }
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

private struct BandCard: View {
    let coordinator: SyncCoordinator
    let onPair: () -> Void

    /// Health only gets data from the automatic hourly sync.
    private var healthExport: String {
        guard let last = coordinator.lastHealthExport, let next = coordinator.nextHealthExport else {
            return "On the next automatic sync"
        }
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        return "\(time(last)) · next around \(time(next))"
    }
    @Environment(\.openURL) private var openURL
    private var band: BandClient { coordinator.band }

    var body: some View {
        Card(title: "Band", systemImage: "applewatch.side.right", color: .gray) {
            LabeledContent("Status", value: band.state.label)
            LabeledContent("Battery", value: band.battery.map { "\($0)%" } ?? "-")
            LabeledContent("Last sync", value: coordinator.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            LabeledContent("Health export", value: healthExport)
            if let start = coordinator.healthStart {
                LabeledContent("Health data since", value: start.formatted(date: .abbreviated, time: .shortened))
            }
            if let report = coordinator.lastReport { ReportRows(report: report) }
            if case .failed(let message) = coordinator.phase {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            if band.pairedID == nil {
                Button("Pair band", action: onPair).buttonStyle(.borderedProminent)
            }
            HStack {
                Button {
                    Task { await coordinator.sync() }
                } label: {
                    Text(coordinator.phase == .syncing ? "Syncing..." : "Sync").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.canSync)
                Button {
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                } label: {
                    Text("Open Health").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Button {
                Task { await coordinator.exportToHealthNow() }
            } label: {
                Label(coordinator.isExporting ? "Exporting..." : "Export to Health now", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.isExporting || coordinator.phase.isBusy)
        }
    }
}

private struct ReportRows: View {
    let report: SyncReport

    var body: some View {
        ForEach(HistoryKind.syncOrder, id: \.self) { kind in
            if let failure = report.failures[kind] {
                LabeledContent(kind.title, value: failure).foregroundStyle(.red)
            } else if let count = report.newRecords[kind], count > 0 {
                LabeledContent(kind.title, value: "+\(count)")
            }
        }
        if report.exportedToHealth {
            LabeledContent("Written to Health", value: "\(report.exportedSamples)")
        }
        if !report.notAllowed.isEmpty {
            LabeledContent("Not allowed in Health", value: report.notAllowed.map(\.rawValue).sorted().joined(separator: ", "))
        }
        if let error = report.exportError {
            LabeledContent("Health error", value: error).foregroundStyle(.red)
        }
    }
}

extension LiveFeed.MeasurementState {
    var problem: String {
        if case .interrupted = self { "Measurement stopped." } else { "No reading. Wear the band snug and keep still." }
    }
}

extension MeasurementKind {
    var title: String {
        switch self {
        case .hrv: "HRV"
        case .heartRate: "heart rate"
        }
    }
}

extension BandClient.State {
    var label: String {
        switch self {
        case .unknown: "Starting"
        case .poweredOff: "Bluetooth off"
        case .unauthorized: "Bluetooth not allowed"
        case .unsupported: "Bluetooth unavailable"
        case .disconnected: "Not connected"
        case .scanning: "Scanning"
        case .connecting: "Connecting"
        case .connected: "Connected"
        }
    }
}

extension HistoryKind {
    var title: String {
        switch self {
        case .activity: "Activity"
        case .continuousHR: "Heart rate"
        case .spotHR: "Heart rate checks"
        case .hrv: "HRV"
        case .spo2: "Blood oxygen"
        case .sleep: "Sleep"
        case .dailyTotals: "Daily totals (stored only)"
        case .workout: "Activities"
        }
    }
}
