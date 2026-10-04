import PulseKit
import SwiftUI

@main
struct PulseBridgeApp: App {
    @State private var coordinator: SyncCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            _coordinator = State(initialValue: SyncCoordinator(container: try RecordStore.container()))
        } catch {
            fatalError("Could not open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await coordinator.appBecameActive() }
            case .background:
                coordinator.appWentToBackground()
                BackgroundRefresh.schedule()
            default: break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            // iOS's time is up: drop the connection so every pending band wait fails fast and the
            // sync ends cleanly (it is incremental, the next run continues).
            await withTaskCancellationHandler {
                await coordinator.backgroundSync()
            } onCancel: {
                Task { @MainActor in coordinator.backgroundSyncExpired() }
            }
            BackgroundRefresh.schedule()
        }
    }
}
