@preconcurrency import HealthKit
import PulseKit

/// A timed challenge session as an Apple Health "Strength training" workout with band heart rate.
@MainActor
final class ChallengeExporter {
    private let store = HKHealthStore()

    func export(_ session: SessionInfo) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), HKQuantityType(.heartRate)], read: [])
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        do {
            try await builder.beginCollection(at: session.start)
            let heart = HealthExporter.heartSamples(session.heart)
            if !heart.isEmpty { try? await builder.addSamples(heart) }
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: session.id.uuidString, HKMetadataKeySyncVersion: 1,
                                           "PulseBridgeReps": session.reps.map { "\($0.name) \($0.count)" }.joined(separator: ", ")])
            try await builder.endCollection(at: session.end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
    }
}
