@preconcurrency import CoreLocation
import Foundation
import Observation
import PulseKit

/// One running activity: phone GPS into the recorder, heart rate from the band's standard heart-rate
/// stream (it resumes by itself after a reconnect). The recorder is saved every 30 s, and once more
/// when finished, so a run survives the app being killed until the user saves or discards it.
@MainActor
@Observable
final class ActivitySession: NSObject {
    /// Heart rate older than this shows as "-".
    static let heartRateStale: TimeInterval = 10

    private(set) var recorder: ActivityRecorder
    private(set) var gpsAccuracy: Double?
    private(set) var locationDenied = false
    private(set) var lastHeartRate: (bpm: Int, at: Date)?
    let id: UUID
    /// The band buzzes when leaving the target zone.
    let zoneAlerts: Bool

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var saver: Task<Void, Never>?

    init(activity: WorkoutActivity, targetZone: Int?, zones: HeartRateZones, zoneAlerts: Bool) {
        id = UUID()
        self.zoneAlerts = zoneAlerts
        recorder = ActivityRecorder(activity: activity, targetZone: targetZone, zones: zones, start: .now)
        super.init()
    }

    func heartRate(at now: Date) -> Int? {
        guard let last = lastHeartRate, now.timeIntervalSince(last.at) <= Self.heartRateStale else { return nil }
        return last.bpm
    }

    func start() {
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        persist()
        saver = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.persist()
            }
        }
    }

    func addHeartRate(_ bpm: Int) {
        lastHeartRate = (bpm, .now)
        recorder.add(heartRate: bpm, at: .now)
    }

    func pause() { recorder.pause(at: .now) }
    func resume() { recorder.resume(at: .now) }

    /// The file stays until the user saves or discards (see `clearUnfinished`).
    func finish() {
        recorder.finish(at: .now)
        manager.stopUpdatingLocation()
        saver?.cancel()
        persist()
    }

    // MARK: Unfinished activity (app killed before Save or Discard)

    private static var unfinishedURL: URL { URL.applicationSupportDirectory.appending(path: "activity-in-progress.json") }

    private struct Unfinished: Codable { let id: UUID; let recorder: ActivityRecorder }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Unfinished(id: id, recorder: recorder)) else { return }
        try? data.write(to: Self.unfinishedURL, options: .atomic)
    }

    /// The saved activity and the time to finish it at: its last GPS fix or heart rate, else the
    /// time the file was last written, else its start.
    static func unfinished() -> (id: UUID, recorder: ActivityRecorder, end: Date)? {
        guard let data = try? Data(contentsOf: unfinishedURL),
              let saved = try? JSONDecoder().decode(Unfinished.self, from: data) else { return nil }
        let written = (try? FileManager.default.attributesOfItem(atPath: unfinishedURL.path)[.modificationDate]) as? Date
        let end = saved.recorder.end ?? saved.recorder.lastEventDate ?? written ?? saved.recorder.start
        return (saved.id, saved.recorder, end)
    }

    /// Cheap check (no decoding) for the Health export gate.
    static var hasUnfinished: Bool { FileManager.default.fileExists(atPath: unfinishedURL.path) }

    static func clearUnfinished() {
        try? FileManager.default.removeItem(at: unfinishedURL)
    }
}

extension ActivitySession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map {
            GeoPoint(date: $0.timestamp, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy)
        }
        MainActor.assumeIsolated {
            for point in points {
                gpsAccuracy = point.accuracy
                recorder.add(point)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { locationDenied = status == .denied || status == .restricted }
    }
}
