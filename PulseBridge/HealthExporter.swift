@preconcurrency import HealthKit
import PulseKit

/// Writes PulseKit samples to HealthKit. Never reads Health data.
@MainActor
final class HealthExporter: HealthWriter {
    private static let batchSize = 500
    private let store = HKHealthStore()

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Workouts carry an active-energy sample, so that type is needed too.
        let types = Set(HealthMetric.allCases.map(\.sampleType)).union([HKQuantityType(.activeEnergyBurned)])
        try await store.requestAuthorization(toShare: types, read: [])
    }

    func save(_ samples: [HealthSample]) async throws -> Set<HealthMetric> {
        let denied = Set(HealthMetric.allCases.filter { store.authorizationStatus(for: $0.sampleType) != .sharingAuthorized })
        let allowed = samples.filter { !denied.contains($0.metric) }
        let objects = allowed.filter { $0.metric != .workout }.map(Self.healthKitSample)
        for start in stride(from: 0, to: objects.count, by: Self.batchSize) {
            try await store.save(Array(objects[start..<min(start + Self.batchSize, objects.count)]))
        }
        // One failing workout must not block the rest: its records stay queued and retry later.
        var failed = Set<HealthMetric>()
        for workout in allowed where workout.metric == .workout {
            do { try await saveWorkout(workout) } catch { failed.insert(.workout) }
        }
        return denied.intersection(samples.map(\.metric)).union(failed)
    }

    /// A workout with its active energy. Distance is not added as a sample: the app already writes
    /// walking distance per 10 minutes, and a second sample for the same minutes would count twice.
    private func saveWorkout(_ sample: HealthSample) async throws {
        guard let info = sample.workout else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = info.activity.healthKitType
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        do {
            try await fill(builder, sample, info)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    private func fill(_ builder: HKWorkoutBuilder, _ sample: HealthSample, _ info: WorkoutInfo) async throws {
        try await builder.beginCollection(at: sample.start)
        // Active energy is optional: skip it when that type isn't allowed instead of failing the workout.
        if info.calories > 0, store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized {
            let energy = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                          quantity: HKQuantity(unit: .kilocalorie(), doubleValue: info.calories),
                                          start: sample.start, end: sample.end)
            try await builder.addSamples([energy])
        }
        var metadata: [String: Any] = [HKMetadataKeySyncIdentifier: sample.syncID, HKMetadataKeySyncVersion: sample.version,
                                       "PulseBridgeSteps": info.steps, "PulseBridgeDistanceMeters": info.distanceMeters]
        if info.heartRate > 0 { metadata["PulseBridgeAverageHeartRate"] = info.heartRate }
        try await builder.addMetadata(metadata)
        try await builder.endCollection(at: sample.end)
    }

    private static func healthKitSample(_ sample: HealthSample) -> HKSample {
        let metadata: [String: Any] = [HKMetadataKeySyncIdentifier: sample.syncID, HKMetadataKeySyncVersion: sample.version]
        if sample.metric == .sleep {
            let stage = SleepStage(rawValue: Int(sample.value)) ?? .core
            return HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stage.healthKitValue.rawValue,
                                    start: sample.start, end: sample.end, metadata: metadata)
        }
        return HKQuantitySample(
            type: HKQuantityType(sample.metric.quantityIdentifier),
            quantity: HKQuantity(unit: sample.metric.unit, doubleValue: sample.value),
            start: sample.start,
            end: sample.end,
            metadata: metadata)
    }
}

private extension HealthMetric {
    var sampleType: HKSampleType {
        switch self {
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .workout: HKObjectType.workoutType()
        default: HKQuantityType(quantityIdentifier)
        }
    }

    var quantityIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .steps: .stepCount
        case .distance: .distanceWalkingRunning
        case .heartRate: .heartRate
        case .hrv: .heartRateVariabilitySDNN
        case .oxygenSaturation: .oxygenSaturation
        case .sleep, .workout: preconditionFailure("not a quantity type")
        }
    }

    var unit: HKUnit {
        switch self {
        case .steps: .count()
        case .distance: .meter()
        case .heartRate: .count().unitDivided(by: .minute())
        case .hrv: .secondUnit(with: .milli)
        case .oxygenSaturation: .percent()
        case .sleep, .workout: .count()
        }
    }
}

private extension SleepStage {
    var healthKitValue: HKCategoryValueSleepAnalysis {
        switch self {
        case .awake: .awake
        case .core: .asleepCore
        case .deep: .asleepDeep
        case .rem: .asleepREM
        }
    }
}

private extension WorkoutActivity {
    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .other: .other
        }
    }
}
