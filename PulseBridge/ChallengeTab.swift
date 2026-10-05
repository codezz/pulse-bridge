import PulseKit
import SwiftUI

/// The Challenge tab: setup, then today's logging, streaks, calendar and totals on one screen.
struct ChallengeTab: View {
    let coordinator: SyncCoordinator
    private var model: ChallengeModel { coordinator.challenge }

    var body: some View {
        NavigationStack {
            if model.isSetUp {
                ChallengeHistoryView(model: model, coordinator: coordinator)
            } else {
                ScrollView {
                    ChallengeCard(model: model, onOpen: {}).padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Challenge")
            }
        }
    }
}
