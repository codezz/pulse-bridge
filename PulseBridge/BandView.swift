import Charts
import PulseBLE
import PulseKit
import SwiftUI

/// The Band tab: the device, sync and Apple Health export, battery, profile, diagnostics.
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
                    DeviceHeader(coordinator: coordinator)
                    BandCard(coordinator: coordinator, onPair: onPair)
                    BatteryCard(coordinator: coordinator)
                    NavigationLink {
                        ProfileView(coordinator: coordinator)
                    } label: {
                        Card(title: "Profile and zones", systemImage: "person.crop.circle", color: .blue, chevron: true) {
                            Text(profileSummary).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    DiagnosticsCard(log: coordinator.diagnostics)
                    if band.pairedID != nil {
                        Button("Forget band", role: .destructive) { confirmForget = true }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .cardBackground()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Band")
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

/// The band at a glance: symbol, name, connection and a battery ring.
private struct DeviceHeader: View {
    let coordinator: SyncCoordinator
    private var band: BandClient { coordinator.band }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "applewatch.side.right")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Palette.band.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pulse One").font(.title3.bold())
                Label(band.state.label, systemImage: "circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(band.state == .connected ? .green : .secondary)
                    .labelStyle(DotLabelStyle())
            }
            Spacer()
            if let battery = band.battery {
                ProgressRing(progress: Double(battery) / 100, color: battery < 20 ? .red : .green, size: 56) {
                    Text("\(battery)%").font(.caption.bold())
                }
                .accessibilityLabel("Battery \(battery) percent")
            }
        }
        .padding()
        .cardBackground()
    }
}

/// A small coloured dot before the text.
private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 8))
            configuration.title.foregroundStyle(.primary)
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

/// The band's battery over the last 30 days, and its average daily use.
private struct BatteryCard: View {
    let coordinator: SyncCoordinator
    @State private var readings: [BatteryReading] = []

    var body: some View {
        Card(title: "Battery", systemImage: batterySymbol(coordinator.band.battery), color: .green) {
            if readings.count < 2 {
                Text("Collecting data: a reading is saved at each connection and sync.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(readings, id: \.date) {
                    LineMark(x: .value("Time", $0.date), y: .value("%", $0.percent))
                }
                .chartYScale(domain: 0...100)
                .foregroundStyle(.green)
                .frame(height: 120)
                Text(BatteryDrain.perDay(readings).map { "About \(Int($0.rounded()))% per day" } ?? "Collecting data for the daily estimate")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(coordinator.lastSync?.timeIntervalSince1970 ?? 0)-\(coordinator.band.battery ?? -1)") {
            readings = (try? coordinator.store.batteryReadings(since: .now.addingTimeInterval(-30 * 86400))) ?? []
        }
    }
}

/// SF Symbol for a battery level.
func batterySymbol(_ percent: Int?) -> String {
    guard let percent else { return "bolt.batteryblock" }   // unknown, not empty
    return switch percent {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
    }
}

private struct BandCard: View {
    let coordinator: SyncCoordinator
    let onPair: () -> Void

    /// Health only gets data from the automatic hourly sync.
    private func healthExport(now: Date) -> String {
        guard let last = coordinator.lastHealthExport, let next = coordinator.nextHealthExport else {
            return "On the next automatic sync"
        }
        return "\(RelativeTime.text(last, now: now)) · next around \(next.formatted(date: .omitted, time: .shortened))"
    }
    @Environment(\.openURL) private var openURL
    private var band: BandClient { coordinator.band }

    var body: some View {
        Card(title: "Sync", systemImage: "arrow.triangle.2.circlepath", color: .blue) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(spacing: 12) {
                    LabeledContent("Last sync", value: coordinator.lastSync.map { RelativeTime.text($0, now: context.date) } ?? "Never")
                    LabeledContent("Health export", value: healthExport(now: context.date))
                    LabeledContent("Background sync", value: coordinator.lastBackgroundSync.map { RelativeTime.text($0, now: context.date) } ?? "Not yet")
                    if UIApplication.shared.backgroundRefreshStatus != .available {
                        Text("Turn on Background App Refresh for Pulse Bridge in Settings to sync without opening the app.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
        case .temperature: "Temperature"
        }
    }
}
