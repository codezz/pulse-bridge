import PulseBLE
import Foundation
import Observation
import PulseKit
import SwiftData
import UIKit

/// UI state around one SyncEngine. Syncs when the app opens (at most once per hour), stays connected
/// while it is in the foreground (live heart rate), and disconnects in the background.
@MainActor
@Observable
final class SyncCoordinator {
    enum Phase: Equatable {
        case idle, connecting, syncing, failed(String)

        var isBusy: Bool { self == .connecting || self == .syncing }
    }

    private static let lastSyncKey = "lastSync"
    private static let lastHealthExportKey = "lastHealthExport"
    private static let lastAutoSyncKey = "lastAutoSyncAttempt"
    private static let lastBackgroundSyncKey = "lastBackgroundSync"
    private static let healthStartKey = "healthStart"
    private static let bandClockOffsetKey = "bandClockOffset"

    let band = BandClient()
    let live = LiveFeed()
    private(set) var heartRate = HeartRateSeries()
    let store: RecordStore
    private(set) var phase: Phase = .idle
    private(set) var lastReport: SyncReport?
    private(set) var lastSync = UserDefaults.standard.object(forKey: SyncCoordinator.lastSyncKey) as? Date
    /// Health gets data from the automatic sync only, at most once per AutoSync.interval.
    private(set) var lastHealthExport = UserDefaults.standard.object(forKey: SyncCoordinator.lastHealthExportKey) as? Date
    var nextHealthExport: Date? { lastHealthExport?.addingTimeInterval(AutoSync.interval) }
    private(set) var isExporting = false
    /// Set at the first sync. Older band history stays on the phone; only newer data goes to Health.
    private(set) var healthStart = UserDefaults.standard.object(forKey: SyncCoordinator.healthStartKey) as? Date
    @ObservationIgnored private let engine: SyncEngine
    /// Band traffic and sync events for bug reports (Band tab > Export diagnostics log).
    let diagnostics: DiagnosticsLog
    private static let profileKey = "userProfile"
    private(set) var profile: UserProfile? = UserDefaults.standard.data(forKey: SyncCoordinator.profileKey)
        .flatMap { try? JSONDecoder().decode(UserProfile.self, from: $0) }
    private(set) var activity: ActivitySession?
    /// A finished activity waiting for Save or Discard.
    private(set) var finishedActivity: ActivitySession?
    @ObservationIgnored private var zoneAlert: ZoneAlert?
    @ObservationIgnored private var isExportingActivities = false
    @ObservationIgnored private let exporter = ActivityExporter()
    @ObservationIgnored private var syncAfterActivity = false
    /// The band as the sync engine and live feed see it, with everything recorded to `diagnostics`.
    @ObservationIgnored private let syncChannel: RecordingChannel
    @ObservationIgnored private let liveChannel: RecordingChannel
    /// Nothing connects or streams while the app is in the background.
    @ObservationIgnored private var isForeground = true
    /// An auto-sync came due during a measurement; it runs when the measurement ends.
    @ObservationIgnored private var syncAfterMeasurement = false

    init(container: ModelContainer) {
        store = RecordStore(container: container)
        engine = SyncEngine(store: store, health: HealthExporter())
        let support = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        diagnostics = DiagnosticsLog(url: support.appending(path: "diagnostics.log"))
        syncChannel = RecordingChannel(band, log: diagnostics)
        // The live stream sends a packet every second and the feed polls; keep only measurements.
        liveChannel = RecordingChannel(band, log: diagnostics, skip: { $0.first == Opcode.realTimeActivity }, logQuiet: false)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        diagnostics.note("app \(version) launched, iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        engine.onBandClockSet = { offset in
            // Saved right away: a sync that fails later must not leave the old offset behind.
            UserDefaults.standard.set(offset, forKey: SyncCoordinator.bandClockOffsetKey)
        }
        band.onHeartRate = { [weak self] bpm in
            self?.heartRate.append(bpm, at: .now)
            self?.activity?.addHeartRate(bpm)
            self?.checkZone(bpm)
        }
        live.onMeasurementEnded = { [weak self] _ in
            guard let self, syncAfterMeasurement else { return }
            syncAfterMeasurement = false
            Task { await self.sync(toHealth: true) }
        }
    }

    /// Sync needs a paired band, Bluetooth not off or denied, and nothing else in flight.
    /// While Bluetooth is still starting up, connect() waits for it.
    var canSync: Bool {
        band.pairedID != nil && !phase.isBusy && band.bluetoothProblem == nil && band.state != .scanning
            && !live.isMeasuring && activity == nil
    }

    func appBecameActive() async {
        isForeground = true
        // Keyed on the last attempt too: if Health export keeps failing, opening the app must not
        // re-read the band every time.
        let lastAttempt = UserDefaults.standard.object(forKey: Self.lastAutoSyncKey) as? Date
        if AutoSync.isDue(lastSync: [lastHealthExport, lastAttempt].compactMap { $0 }.max()) {
            if !live.isMeasuring && !hasPendingActivity { UserDefaults.standard.set(Date(), forKey: Self.lastAutoSyncKey) }
            if live.isMeasuring {
                syncAfterMeasurement = true
            } else if hasPendingActivity {
                // Don't read the band history or touch Health mid-activity; reconnect for heart rate.
                syncAfterActivity = true
                await connectForLiveData()
            } else {
                await sync(toHealth: true)
            }
        } else {
            await connectForLiveData()
        }
    }

    /// Within the hour: no sync, just connect so battery and live heart rate show. Already connected
    /// (an activity kept the band in the background): restart the live feed.
    private func connectForLiveData() async {
        guard band.pairedID != nil, !phase.isBusy, band.bluetoothProblem == nil else { return }
        guard band.state != .connected else { return await startLive() }
        phase = .connecting
        do {
            try await band.connect()
            logConnection()
            await loadProfileIfNeeded()
            await startLive()
            phase = .idle
        } catch PulseError.busy {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
            diagnostics.note("connect failed: \(error.localizedDescription)")
        }
    }

    /// The live feed stops in the background. A locked phone mid-run keeps the band connected:
    /// heart rate comes from the standard stream, not the feed.
    func appWentToBackground() {
        isForeground = false
        Task {
            await live.stop()
            // The app may have come back while the feed was stopping.
            if !isForeground && activity == nil { band.disconnect() }
        }
    }

    /// Set time, pull new history, store it, write it to Health. The connection stays open for live data.
    /// Manual sync (button, pull to refresh) reads the band only; the automatic hourly sync passes
    /// `toHealth: true` and also exports everything queued to Apple Health.
    /// `quiet`: a background sync, no haptic.
    func sync(toHealth: Bool = false, quiet: Bool = false) async {
        guard canSync else { return }
        let previous = phase
        phase = .connecting
        diagnostics.note("sync started (\(toHealth ? "band + Health" : "band only"))")
        do {
            try await band.connect()
            logConnection()
            await live.stop() // the sync becomes the channel's only reader
            await loadProfileIfNeeded()
            phase = .syncing
            let report = try await syncResumingOnce(toHealth: toHealth && !hasPendingActivity)
            diagnostics.note("sync finished: \(Self.summary(report))")
            lastReport = report
            let now = Date()
            lastSync = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            cachedHeartRateProfile = nil
            if report.exportedToHealth {
                lastHealthExport = now
                UserDefaults.standard.set(now, forKey: Self.lastHealthExportKey)
            }
            if toHealth && !hasPendingActivity { await exportPendingActivities() }
            phase = .idle
            if !toHealth && !quiet { manualSyncFeedback = SyncFeedback(count: manualSyncFeedback.count + 1, succeeded: true) }
        } catch PulseError.busy {
            // Another connect or sync owns the band; leave its connection alone.
            phase = previous
            diagnostics.note("sync skipped: busy")
        } catch {
            phase = .failed(error.localizedDescription)
            diagnostics.note("sync failed: \(error.localizedDescription)")
            if !toHealth && !quiet { manualSyncFeedback = SyncFeedback(count: manualSyncFeedback.count + 1, succeeded: false) }
        }
        await startLive()
    }

    // MARK: Background sync

    private(set) var lastBackgroundSync = UserDefaults.standard.object(forKey: SyncCoordinator.lastBackgroundSyncKey) as? Date

    /// A background refresh: same hourly rule as opening the app. A band out of reach isn't an
    /// attempt, so the next app open syncs right away. Health only while the phone is unlocked.
    func backgroundSync() async {
        // Launched by iOS only for this task: no scene came to the foreground.
        if UIApplication.shared.applicationState != .active { isForeground = false }
        let lastAttempt = UserDefaults.standard.object(forKey: Self.lastAutoSyncKey) as? Date
        let busy = phase.isBusy || live.isMeasuring || hasPendingActivity
        guard BackgroundSync.shouldRun(lastExport: lastHealthExport, lastAttempt: lastAttempt,
                                       paired: band.pairedID != nil, busy: busy, now: .now) else { return }
        diagnostics.note("background sync started")
        do {
            try await band.connect()
        } catch {
            diagnostics.note("background sync: band not in range (\(error.localizedDescription))")
            return
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: Self.lastAutoSyncKey)
        await sync(toHealth: UIApplication.shared.isProtectedDataAvailable, quiet: true)
        lastBackgroundSync = now
        UserDefaults.standard.set(now, forKey: Self.lastBackgroundSyncKey)
        if !isForeground { band.disconnect() }
    }

    private func logConnection() {
        let serial = band.serial.map { "...\($0.suffix(2))" } ?? "?"
        diagnostics.note("connected: band \(serial), battery \(band.battery.map { "\($0)%" } ?? "?")")
    }

    /// One line per sync for the diagnostics log.
    private static func summary(_ report: SyncReport) -> String {
        let new = HistoryKind.syncOrder.map { "\($0)=\(report.newRecords[$0] ?? 0)" }.joined(separator: " ")
        let failures = report.failures.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "; ")
        var parts = ["new \(new)", "dropped \(report.dropped)"]
        if report.exportedToHealth { parts.append("Health \(report.exportedSamples)") }
        if !report.notAllowed.isEmpty { parts.append("not allowed \(report.notAllowed.map(\.rawValue).sorted())") }
        if let error = report.exportError { parts.append("Health error \(error)") }
        if !failures.isEmpty { parts.append("failed \(failures)") }
        return parts.joined(separator: ", ")
    }

    /// "Export to Health now": writes what earlier syncs stored, without talking to the band.
    func exportToHealthNow() async {
        guard !phase.isBusy, !isExporting, !hasPendingActivity else { return }
        isExporting = true
        defer { isExporting = false }
        let report = await engine.exportToHealth()
        diagnostics.note("Health export: \(report.exportedToHealth ? "\(report.exportedSamples) samples" : report.exportError ?? "failed")")
        lastReport = report
        if report.exportedToHealth {
            let now = Date()
            lastHealthExport = now
            UserDefaults.standard.set(now, forKey: Self.lastHealthExportKey)
        }
        await exportPendingActivities()
    }

    /// Live heart rate on the Summary card. The band's stream is also on during an activity.
    private(set) var isLiveHeartRateOn = false
    /// Zones for the live line, taken when live starts (computing them reads 180 days of data).
    private(set) var liveZones: HeartRateZones?

    /// Changes when a sync the user started (button, pull to refresh) ends, for its haptic.
    struct SyncFeedback: Equatable {
        var count = 0
        var succeeded = true
    }
    private(set) var manualSyncFeedback = SyncFeedback()

    /// Live heart rate on demand: turns the band's heart-rate stream on with an empty chart.
    func startLiveHeartRate() {
        heartRate = HeartRateSeries()
        liveZones = heartRateProfile().zones
        isLiveHeartRateOn = true
        band.streamsHeartRate = true
    }

    func stopLiveHeartRate() {
        isLiveHeartRateOn = false
        if activity == nil { band.streamsHeartRate = false }
    }

    // MARK: Profile and heart-rate zones

    /// First connection: take the profile the band already has (`42`).
    private func loadProfileIfNeeded() async {
        guard profile == nil, band.state == .connected, !live.isRunning else { return }
        try? await syncChannel.send(Command.readProfile)
        while let packet = try? await syncChannel.nextPacket(timeout: .seconds(2)) {
            if let found = UserProfile(bandPacket: packet, now: .now, calendar: .current) {
                storeProfile(found)
                diagnostics.note("profile read from band")
                return
            }
        }
    }

    func saveProfile(_ new: UserProfile) async {
        storeProfile(new)
        guard band.state == .connected, !phase.isBusy, activity == nil, !live.isMeasuring else { return }
        await live.stop()
        try? await syncChannel.send(new.command(at: .now, calendar: .current))
        _ = try? await syncChannel.nextPacket(timeout: .seconds(2))
        await startLive()
    }

    private func storeProfile(_ new: UserProfile) {
        profile = new
        cachedHeartRateProfile = nil
        UserDefaults.standard.set(try? JSONEncoder().encode(new), forKey: Self.profileKey)
    }

    /// Computed from stored data; kept until a sync, a profile change or a saved activity, or for an hour.
    @ObservationIgnored private var cachedHeartRateProfile: (value: HeartRateProfile, at: Date)?

    func heartRateProfile() -> HeartRateProfile {
        let now = Date()
        if let cached = cachedHeartRateProfile, now.timeIntervalSince(cached.at) < AutoSync.interval { return cached.value }
        let value = computeHeartRateProfile(now: now)
        cachedHeartRateProfile = (value, now)
        return value
    }

    private func computeHeartRateProfile(now: Date) -> HeartRateProfile {
        let age = profile?.age(at: now, calendar: .current) ?? 40
        let heart = (try? store.records(of: [.spotHR, .continuousHR], from: now.addingTimeInterval(-HeartRateProfile.lookBack), to: now))
            .map { Readings(records: $0).heartRate } ?? []
        let recorded = ((try? store.activities(from: now.addingTimeInterval(-HeartRateProfile.lookBack), to: now)) ?? [])
            .compactMap(\.recorder).flatMap { HeartRateProfile.minuteMedians($0.heart.map { Reading(date: $0.date, value: Double($0.bpm)) }) }
        let metrics = try? SummaryService(store: store).load(days: 14, endingOn: now)
        let nights = metrics.map { m in m.days.compactMap { m.restingHeartRate(on: $0) } } ?? []
        return HeartRateProfile(age: age, heartRate: heart + recorded, nightlyResting: nights, now: now)
    }

    // MARK: Activities

    /// An activity is running, finished but not saved or discarded, or left over from a crash. While
    /// one exists, Health export waits: its time span must not get the band's distance too.
    var hasPendingActivity: Bool {
        activity != nil || finishedActivity != nil || ActivitySession.hasUnfinished
    }

    func startActivity(_ type: WorkoutActivity, targetZone: Int?, zoneAlerts: Bool) async {
        guard activity == nil, !phase.isBusy, !live.isMeasuring else { return }
        let zones = heartRateProfile().zones
        let alerts = zoneAlerts && targetZone != nil
        let session = ActivitySession(activity: type, targetZone: targetZone, zones: zones, zoneAlerts: alerts)
        activity = session
        zoneAlert = alerts ? targetZone.map { ZoneAlert(target: zones.range(of: $0)) } : nil
        diagnostics.note("activity started: \(type.rawValue), target zone \(targetZone.map(String.init) ?? "free"), alerts \(alerts ? "on" : "off")")
        band.streamsHeartRate = true
        band.keepConnected = true
        session.start()
        // The band has no screen: 3 buzzes confirm the start.
        await buzz(times: 3)
    }

    /// Buzzes when the activity's heart rate stays out of the target zone (see ZoneAlert).
    private func checkZone(_ bpm: Int) {
        guard let session = activity, session.recorder.state == .recording else { zoneAlert?.reset(); return }
        guard let direction = zoneAlert?.update(bpm: bpm, at: .now) else { return }
        diagnostics.note("zone alert: \(direction == .above ? "above" : "below") target")
        Task { await buzz(times: ZoneAlert.buzzes(for: direction)) }
    }

    /// The live feed reads (and ignores) the ack in the foreground; in the background nobody does,
    /// so take it here instead of leaving it for the next sync to misread.
    private func buzz(times: Int) async {
        guard band.state == .connected else { return }
        if live.isRunning {
            try? await liveChannel.send(Command.vibrate(times: times))
        } else {
            try? await syncChannel.send(Command.vibrate(times: times))
            _ = try? await syncChannel.nextPacket(timeout: .seconds(2))
        }
    }

    func finishActivity() {
        guard let session = activity else { return }
        session.finish()
        activity = nil
        finishedActivity = session
        band.streamsHeartRate = isLiveHeartRateOn
        band.keepConnected = false
        zoneAlert = nil
        diagnostics.note("activity finished: \(Int(session.recorder.distance)) m")
    }

    /// Save stores the activity and writes it to Health right away; Discard drops it.
    func closeFinishedActivity(save: Bool) async {
        guard let session = finishedActivity else { return }
        finishedActivity = nil
        if save {
            // The recovery file is the only other copy: keep it unless the save worked.
            do {
                try store.save(session.recorder, id: session.id)
            } catch {
                diagnostics.note("activity save failed, kept for recovery: \(error.localizedDescription)")
                return
            }
        }
        if save { cachedHeartRateProfile = nil }
        ActivitySession.clearUnfinished()
        await exportPendingActivities()
        await runDeferredSync()
    }

    /// The app was killed during (or right after) an activity: finish it at its last event and save it.
    func saveRecovered(id: UUID, recorder: ActivityRecorder, end: Date) async {
        var finished = recorder
        if finished.state != .finished { finished.finish(at: end) }
        do {
            try store.save(finished, id: id)
        } catch {
            diagnostics.note("recovered activity save failed, kept for next launch: \(error.localizedDescription)")
            return
        }
        cachedHeartRateProfile = nil
        ActivitySession.clearUnfinished()
        await exportPendingActivities()
        await runDeferredSync()
    }

    func discardRecovered() async {
        ActivitySession.clearUnfinished()
        await runDeferredSync()
    }

    private func runDeferredSync() async {
        guard syncAfterActivity, !hasPendingActivity else { return }
        syncAfterActivity = false
        await sync(toHealth: true)
    }

    /// One export at a time, so the same activity can't reach Health twice.
    func exportPendingActivities() async {
        guard !isExportingActivities else { return }
        isExportingActivities = true
        defer { isExportingActivities = false }
        for stored in (try? store.pendingActivities()) ?? [] {
            guard let recorder = stored.recorder else { continue }
            do {
                try await exporter.export(recorder, id: stored.id)
                try? store.markActivityExported([stored])
                diagnostics.note("activity exported to Health")
            } catch {
                diagnostics.note("activity export failed: \(error.localizedDescription)")
            }
        }
    }

    /// HRV or a 30 s heart-rate reading. Results show on Summary; HRV also reaches Health
    /// through the band's history on the next sync.
    func measure(_ kind: MeasurementKind) async {
        guard band.state == .connected, !phase.isBusy, activity == nil else { return }
        if !live.isRunning { await startLive() }
        try? await live.measure(kind)
    }

    private func startLive() async {
        guard isForeground, band.state == .connected else { return }
        try? await live.start(over: liveChannel)
    }

    /// The band drops out when it moves out of range. Sync is incremental, so reconnecting once
    /// continues where it stopped.
    private func syncResumingOnce(toHealth: Bool) async throws -> SyncReport {
        do {
            return try await syncOnce(toHealth: toHealth)
        } catch PulseError.notConnected where isForeground {
            try await band.connect()
            return try await syncOnce(toHealth: toHealth)
        }
    }

    /// Reads records in the offset the band clock was last set to, then remembers the new one.
    private func syncOnce(toHealth: Bool) async throws -> SyncReport {
        let defaults = UserDefaults.standard
        let previousOffset = defaults.object(forKey: Self.bandClockOffsetKey) as? Int
        let report = try await engine.sync(over: syncChannel, serial: band.serial ?? "unknown",
                                           healthStart: startHealthIfNeeded(), bandClockOffset: previousOffset, exportToHealth: toHealth)
        defaults.set(report.bandClockOffset, forKey: Self.bandClockOffsetKey)
        return report
    }

    private func startHealthIfNeeded() -> Date {
        if let healthStart { return healthStart }
        let now = Date()
        healthStart = now
        UserDefaults.standard.set(now, forKey: Self.healthStartKey)
        return now
    }
}
