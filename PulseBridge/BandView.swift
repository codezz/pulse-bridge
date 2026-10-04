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
                    BatteryCard(coordinator: coordinator)
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
        .task(id: coordinator.lastSync) {
            readings = (try? coordinator.store.batteryReadings(since: .now.addingTimeInterval(-30 * 86400))) ?? []
        }
    }
}

/// SF Symbol for a battery level.
func batterySymbol(_ percent: Int?) -> String {
    switch percent ?? 0 {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
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

/// Shared card chrome, with an optional control at the right of the title.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    var color: Color = .gray
    @ViewBuilder let content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemImage: systemImage, color: color)
                Text(title).font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension Card where Accessory == EmptyView {
    init(title: String, systemImage: String, color: Color = .gray, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, color: color, content: content, accessory: { EmptyView() })
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
        Card(title: "Band", systemImage: "applewatch.side.right", color: .gray) {
            LabeledContent("Status", value: band.state.label)
            LabeledContent("Battery", value: band.battery.map { "\($0)%" } ?? "-")
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
        }
    }
}
