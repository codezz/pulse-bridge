import Foundation
import os

@MainActor
public protocol HealthWriter: AnyObject {
    func requestAuthorization() async throws
    /// Saves what it is allowed to; returns the metrics it was not allowed to write.
    func save(_ samples: [HealthSample]) async throws -> Set<HealthMetric>
}

public struct SyncReport: Sendable, Equatable {
    public var newRecords: [HistoryKind: Int] = [:]
    public var dropped = 0
    public var exportedSamples = 0
    public var notAllowed: Set<HealthMetric> = []
    public var failures: [HistoryKind: String] = [:]
    public var exportError: String?
    /// False for a band-only sync: new records wait in the export queue for the next full sync.
    public var exportedToHealth = false
    /// UTC offset (seconds) the band clock was set to in this sync. Pass it to the next sync.
    public var bandClockOffset = 0

    public init() {}
}

/// One sync: set the band clock, read every kind incrementally, store, export to Health.
@MainActor
public final class SyncEngine {
    private static let log = Logger(subsystem: "ro.codez.pulsebridge", category: "sync")

    /// Records dated further ahead than this come from a wrong band clock.
    static let futureTolerance: TimeInterval = 24 * 3600
    /// Re-read this far behind the cursor: catches time-zone and DST shifts of the band clock
    /// and records that were still being filled. Duplicates are removed by ID in the store.
    static let rereadWindow: TimeInterval = 26 * 3600

    private let store: RecordStore
    private let health: HealthWriter
    private let reader: HistoryReader
    private let now: () -> Date
    private var isRunning = false
    /// Called as soon as the band clock is set, so the offset survives a sync that fails later.
    public var onBandClockSet: ((Int) -> Void)?

    public init(store: RecordStore, health: HealthWriter, reader: HistoryReader = HistoryReader(), now: @escaping () -> Date = Date.init) {
        self.store = store
        self.health = health
        self.reader = reader
        self.now = now
    }

    /// `healthStart`: records older than this are stored on the phone but never written to Health.
    /// `bandClockOffset`: the UTC offset the band clock was set to by the previous sync. The band stores
    /// wall-clock times without a zone, so records made since then are read in that offset, which
    /// keeps travel and daylight-saving changes from shifting them. Nil uses the phone's zone.
    /// `exportToHealth`: false reads the band into the store only (manual sync); the hourly
    /// automatic sync passes true and also writes everything queued to Health.
    public func sync(over channel: some CommandChannel, serial: String, healthStart: Date? = nil,
                     bandClockOffset: Int? = nil, exportToHealth: Bool = true) async throws -> SyncReport {
        guard !isRunning else { throw PulseError.busy }
        isRunning = true
        defer { isRunning = false }

        var recordReader = reader
        if let offset = bandClockOffset.flatMap(TimeZone.init(secondsFromGMT:)) { recordReader.timeZone = offset }
        var report = SyncReport()
        report.bandClockOffset = try await setTime(over: channel)
        onBandClockSet?(report.bandClockOffset)
        for kind in HistoryKind.syncOrder {
            do {
                // A record slightly in the future must not move the cursor past now.
                let cursor = try store.latestStart(of: kind).map { min($0, now()).addingTimeInterval(-Self.rereadWindow) }
                let result = try await recordReader.read(kind, newerThan: cursor, over: channel)
                let limit = now().addingTimeInterval(Self.futureTolerance)
                let valid = result.records.filter { $0.start <= limit }
                let dropped = result.dropped + result.records.count - valid.count
                if dropped > 0 { Self.log.notice("\(String(describing: kind)): dropped \(dropped) unreadable or future-dated records") }
                report.dropped += dropped
                report.newRecords[kind] = try store.insert(valid, serial: serial, healthStart: healthStart)
            } catch PulseError.notConnected {
                throw PulseError.notConnected
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.log.error("\(String(describing: kind)) failed: \(logText(error))")
                report.failures[kind] = error.localizedDescription
            }
        }
        if exportToHealth {
            await export(into: &report)
            report.exportedToHealth = report.exportError == nil
        }
        return report
    }

    /// Manual "Export to Health now": writes everything waiting in the store, no band needed.
    public func exportToHealth() async -> SyncReport {
        var report = SyncReport()
        guard !isRunning else {
            report.exportError = PulseError.busy.localizedDescription
            return report
        }
        isRunning = true
        defer { isRunning = false }
        await export(into: &report)
        report.exportedToHealth = report.exportError == nil
        return report
    }

    /// Sets the band to the phone's local time and returns that UTC offset.
    /// The band sometimes ignores the first command after a reconnect, so set-time is retried.
    private func setTime(over channel: some CommandChannel) async throws -> Int {
        for _ in 1...3 {
            let date = now()
            try await channel.send(Command.setTime(date, in: reader.timeZone))
            while let packet = try await channel.nextPacket(timeout: .seconds(2)) {
                if packet.first == Opcode.setTime { return reader.timeZone.secondsFromGMT(for: date) }
            }
        }
        throw PulseError.noResponse(Opcode.setTime)
    }

    /// Exports every queued record. Records with a metric Health refused stay queued.
    private func export(into report: inout SyncReport) async {
        do {
            try await health.requestAuthorization()
            let batches = try store.pendingExport().compactMap { stored in
                stored.historyRecord.map { (stored, $0.healthSamples(id: stored.id, version: stored.version)) }
            }
            // A GPS activity already writes distance and its own workout for its time span.
            let samples = batches.flatMap(\.1)
            let spans = try store.activityIntervals(from: samples.map(\.start).min() ?? .distantPast,
                                                    to: samples.map(\.end).max() ?? .distantFuture)
            let notAllowed = try await health.save(samples.filter { sample in
                !([.distance, .workout, .heartRate].contains(sample.metric)
                  && spans.contains { $0.start < Swift.max(sample.end, sample.start.addingTimeInterval(1)) && sample.start < $0.end })
            })
            let done = batches.filter { _, samples in samples.allSatisfy { !notAllowed.contains($0.metric) } }
            try store.markExported(done.map(\.0))
            report.exportedSamples = done.reduce(0) { $0 + $1.1.count }
            report.notAllowed = notAllowed
        } catch {
            report.exportError = error.localizedDescription
        }
    }
}
