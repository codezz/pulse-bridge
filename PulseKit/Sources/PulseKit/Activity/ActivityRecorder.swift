import Foundation

public struct GeoPoint: Codable, Sendable, Equatable {
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    /// Horizontal accuracy in meters.
    public let accuracy: Double

    public init(date: Date, latitude: Double, longitude: Double, accuracy: Double) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }
}

public struct HeartSample: Codable, Sendable, Equatable {
    public let date: Date
    public let bpm: Int

    public init(date: Date, bpm: Int) {
        self.date = date
        self.bpm = bpm
    }
}

/// One activity as it is recorded: GPS points (split into segments at each pause), heart rate,
/// distance, km splits and time in zones. Pure and Codable, so it can be saved mid-run.
public struct ActivityRecorder: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case recording, paused, finished }

    public static let maxAccuracy = 30.0
    /// Faster than this between two fixes is a GPS jump (m/s).
    public static func maxSpeed(for activity: WorkoutActivity) -> Double { activity == .cycling ? 30 : 12 }
    public static let paceWindow: TimeInterval = 30
    public static let maxHeartGap: TimeInterval = 10

    public let activity: WorkoutActivity
    public let targetZone: Int?
    public let zones: HeartRateZones
    public let start: Date
    public private(set) var state: State = .recording
    public private(set) var end: Date?
    /// Accepted GPS points; a new segment starts at each resume, so pauses add no distance.
    public private(set) var segments: [[GeoPoint]] = [[]]
    public private(set) var heart: [HeartSample] = []
    /// Meters.
    public private(set) var distance: Double = 0
    /// Moving time at each completed kilometer.
    public private(set) var splits: [TimeInterval] = []
    public private(set) var timeInZone: [Int: TimeInterval] = [:]
    /// Each pause, for Health's pause/resume events.
    public private(set) var pauses: [DateInterval] = []
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    /// Fixes taken before this (the start or the last resume) are stale: CoreLocation delivers cached ones.
    private var acceptFrom: Date

    public init(activity: WorkoutActivity, targetZone: Int?, zones: HeartRateZones, start: Date) {
        self.activity = activity
        self.targetZone = targetZone
        self.zones = zones
        self.start = start
        acceptFrom = start
    }

    public var points: [GeoPoint] { segments.flatMap { $0 } }

    public mutating func add(_ point: GeoPoint) {
        guard state == .recording, point.accuracy <= Self.maxAccuracy, point.date >= acceptFrom else { return }
        if let last = segments[segments.count - 1].last {
            let seconds = point.date.timeIntervalSince(last.date)
            guard seconds > 0 else { return }
            let meters = Self.meters(last, point)
            guard meters / seconds <= Self.maxSpeed(for: activity) else { return }
            let before = distance
            distance += meters
            if Int(distance / 1000) > Int(before / 1000) { splits.append(movingTime(at: point.date)) }
        }
        segments[segments.count - 1].append(point)
    }

    public mutating func add(heartRate bpm: Int, at date: Date) {
        guard state == .recording, bpm > 0 else { return }
        if let last = heart.last {
            let seconds = min(date.timeIntervalSince(last.date), Self.maxHeartGap)
            if seconds > 0 { timeInZone[zones.zone(for: last.bpm), default: 0] += seconds }
        }
        heart.append(HeartSample(date: date, bpm: bpm))
    }

    public mutating func pause(at date: Date) {
        guard state == .recording else { return }
        state = .paused
        pausedAt = date
    }

    public mutating func resume(at date: Date) {
        guard state == .paused, let pausedAt else { return }
        pausedTotal += date.timeIntervalSince(pausedAt)
        pauses.append(DateInterval(start: pausedAt, end: Swift.max(pausedAt, date)))
        self.pausedAt = nil
        acceptFrom = date
        segments.append([])
        state = .recording
    }

    public mutating func finish(at date: Date) {
        if state == .paused { resume(at: date) }
        state = .finished
        end = date
    }

    public func movingTime(at now: Date) -> TimeInterval {
        let until = end ?? pausedAt ?? now
        return Swift.max(0, until.timeIntervalSince(start) - pausedTotal)
    }

    /// Seconds per km over the last 30 s of the current segment; nil when barely moving.
    public func currentPace(at now: Date) -> TimeInterval? {
        let recent = segments[segments.count - 1].filter { $0.date >= now.addingTimeInterval(-Self.paceWindow) }
        guard let first = recent.first, let last = recent.last, last.date > first.date else { return nil }
        let meters = zip(recent, recent.dropFirst()).reduce(0) { $0 + Self.meters($1.0, $1.1) }
        guard meters >= 20 else { return nil }
        return last.date.timeIntervalSince(first.date) / (meters / 1000)
    }

    public func averagePace(at now: Date) -> TimeInterval? {
        distance >= 50 ? movingTime(at: now) / (distance / 1000) : nil
    }

    /// The newest GPS fix or heart-rate sample (for finishing an activity recovered after a crash).
    public var lastEventDate: Date? { [points.last?.date, heart.last?.date].compactMap { $0 }.max() }

    public var averageHeartRate: Int? { heart.isEmpty ? nil : heart.map(\.bpm).reduce(0, +) / heart.count }
    public var maxHeartRate: Int? { heart.map(\.bpm).max() }
    public var splitDurations: [TimeInterval] { zip(splits, [0] + splits).map { $0 - $1 } }
    public var timeInTarget: TimeInterval { targetZone.map { timeInZone[$0] ?? 0 } ?? 0 }

    /// Great-circle distance in meters (haversine).
    public static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, h.squareRoot()))
    }
}
