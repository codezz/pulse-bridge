@preconcurrency import CoreLocation
@preconcurrency import HealthKit
import PulseKit

/// Saves a recorded activity as an Apple Health workout with distance, heart rate, pauses and its route.
@MainActor
final class ActivityExporter {
    private let store = HKHealthStore()

    /// Throws only if no workout was saved (then nothing is left behind). Heart rate and the route are
    /// best effort: a refused or failed part doesn't block the workout.
    func export(_ recorder: ActivityRecorder, id: UUID) async throws {
        guard HKHealthStore.isHealthDataAvailable(), let end = recorder.end else { return }
        let distanceType = HKQuantityType(recorder.activity == .cycling ? .distanceCycling : .distanceWalkingRunning)
        try await store.requestAuthorization(
            toShare: [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distanceType, HKQuantityType(.heartRate)], read: [])
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch recorder.activity {
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .other: .other
        }
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: nil)
        let workout: HKWorkout?
        do {
            try await builder.beginCollection(at: recorder.start)
            let distance = Self.distanceSamples(recorder, type: distanceType)
            if !distance.isEmpty { try await builder.addSamples(distance) }
            let heart = HealthExporter.heartSamples(recorder.heart)
            if !heart.isEmpty { try? await builder.addSamples(heart) }
            let events = recorder.pauses.flatMap {
                [HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: $0.start, duration: 0), metadata: nil),
                 HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: $0.end, duration: 0), metadata: nil)]
            }
            if !events.isEmpty { try await builder.addWorkoutEvents(events) }
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: id.uuidString, HKMetadataKeySyncVersion: 1,
                                           HKMetadataKeyIndoorWorkout: false])
            try await builder.endCollection(at: end)
            workout = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
        let points = recorder.points
        guard let workout, points.count > 1 else { return }
        let route = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        do {
            try await route.insertRouteData(points.map {
                CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude), altitude: 0,
                           horizontalAccuracy: $0.accuracy, verticalAccuracy: -1, timestamp: $0.date)
            })
            _ = try await route.finishRoute(with: workout, metadata: nil)
        } catch {
            route.discard()
        }
    }

    /// One distance sample per minute of movement, per segment (pauses add nothing).
    private static func distanceSamples(_ recorder: ActivityRecorder, type: HKQuantityType) -> [HKSample] {
        var result: [HKSample] = []
        for segment in recorder.segments where segment.count > 1 {
            var chunkStart = segment[0].date, meters = 0.0
            for (a, b) in zip(segment, segment.dropFirst()) {
                meters += ActivityRecorder.meters(a, b)
                if b.date.timeIntervalSince(chunkStart) >= 60 || b == segment.last {
                    if meters > 0 {
                        result.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                                                       start: chunkStart, end: b.date))
                    }
                    chunkStart = b.date
                    meters = 0
                }
            }
        }
        return result
    }
}
