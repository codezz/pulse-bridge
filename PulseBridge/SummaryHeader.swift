import PulseBLE
import PulseKit
import SwiftUI

/// One status line at the top of Summary: band connection, battery, last sync. Taps open the Band tab.
struct SummaryHeader: View {
    let coordinator: SyncCoordinator
    let onTap: () -> Void

    private var band: BandClient { coordinator.band }

    private var dotColor: Color {
        if band.bluetoothProblem != nil { return .orange }
        if case .failed = coordinator.phase { return .orange }
        return band.state == .connected ? .green : .gray
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                if let battery = band.battery, band.state == .connected {
                    Label("\(battery)%", systemImage: "battery.75percent").labelStyle(.titleAndIcon)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    status(now: context.date)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Only syncs the user started; the hourly automatic one stays silent.
        .sensoryFeedback(trigger: coordinator.manualSyncFeedback) { _, new in new.succeeded ? .success : .error }
    }

    @ViewBuilder private func status(now: Date) -> some View {
        switch coordinator.phase {
        case .connecting:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Connecting...") }
        case .syncing:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Syncing...") }
        case .failed:
            Text("Sync failed").foregroundStyle(.orange)
        case .idle:
            Text(coordinator.lastSync.map { "Synced \(RelativeTime.text($0, now: now))" } ?? "Not synced yet")
        }
    }
}
