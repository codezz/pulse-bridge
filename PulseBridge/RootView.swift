import Combine
import PulseBLE
import PulseKit
import SwiftUI

enum AppTab: Hashable { case today, trends, challenge, band }

struct RootView: View {
    let coordinator: SyncCoordinator
    @State private var summary: SummaryModel
    @State private var showPairing = false
    @State private var tab = AppTab.today
    @State private var unfinished: (id: UUID, recorder: ActivityRecorder, end: Date)?
    @State private var showUnfinished = false
    @Environment(\.scenePhase) private var scenePhase

    init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
        _summary = State(initialValue: SummaryModel(service: SummaryService(store: coordinator.store)))
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                SummaryView(coordinator: coordinator, model: summary, onShowBand: { tab = .band }, onShowChallenge: { tab = .challenge })
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.trends) {
                TrendsView(service: summary.service)
            }
            Tab("Challenge", systemImage: "figure.strengthtraining.traditional", value: AppTab.challenge) {
                ChallengeTab(coordinator: coordinator)
            }
            Tab("Band", systemImage: "applewatch.side.right", value: AppTab.band) {
                BandView(coordinator: coordinator, onPair: { showPairing = true })
            }
        }
        .tint(Color(red: 0.93, green: 0.22, blue: 0.43)) // the app icon's pink
        .fullScreenCover(isPresented: Binding(get: { coordinator.activity != nil || coordinator.finishedActivity != nil },
                                              set: { _ in })) {
            ActivityCover(coordinator: coordinator)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: coordinator.activity != nil)
        .alert("Unfinished activity", isPresented: $showUnfinished, presenting: unfinished) { pending in
            Button("Save") { Task { await coordinator.saveRecovered(id: pending.id, recorder: pending.recorder, end: pending.end) } }
            Button("Discard", role: .destructive) { Task { await coordinator.discardRecovered() } }
        } message: { pending in
            Text("An activity from \(pending.recorder.start.formatted(date: .abbreviated, time: .shortened)) (\(kmText(pending.recorder.distance))) was not saved. Save it?")
        }
        .sheet(isPresented: $showPairing, onDismiss: { Task { await coordinator.appBecameActive() } }) {
            PairingView(band: coordinator.band)
        }
        .onAppear {
            showPairing = coordinator.band.pairedID == nil
            if coordinator.activity == nil, coordinator.finishedActivity == nil, let pending = ActivitySession.unfinished() { unfinished = pending; showUnfinished = true }
            summary.reload()
        }
        .onChange(of: coordinator.lastSync) { summary.reload() }
        // "Today" and "last night" move at midnight and while the app was closed.
        .onChange(of: scenePhase) { _, phase in if phase == .active { summary.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in summary.reload() }
    }
}
