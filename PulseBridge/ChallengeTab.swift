import PulseKit
import SwiftUI

/// The Challenge tab: setup, then today's logging and the history.
struct ChallengeTab: View {
    let coordinator: SyncCoordinator
    @State private var showLogger = false
    private var model: ChallengeModel { coordinator.challenge }

    var body: some View {
        NavigationStack {
            Group {
                if model.isSetUp {
                    ChallengeHistoryView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Log", systemImage: "plus") { showLogger = true }
                            }
                        }
                } else {
                    ScrollView {
                        ChallengeCard(model: model, onLog: {}, onOpen: {}).padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Challenge")
                }
            }
        }
        .sheet(isPresented: $showLogger) { ChallengeLogger(model: model, coordinator: coordinator) }
    }
}
