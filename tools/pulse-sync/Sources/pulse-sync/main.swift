import Foundation
import PulseBLE
import PulseKit
import SwiftData

/// Runs the app's real SyncEngine against the band from the Mac. `--help` lists the options.
/// State (database, Health ledger, Health start) lives in tools/pulse-sync/.state/.
let usage = """
    usage: swift run --package-path tools/pulse-sync pulse-sync [options]

    Sync (default): connects, sets the time, reads new history into tools/pulse-sync/.state/.
      --device UUID              band to use (default: tools/ble-probe/.device)
      --tz Area/City             time zone for the band clock (default: this Mac's)
      --health-start ISO8601     only newer data counts as sent to Health (default: first run)
      --fresh                    delete the local state first
      --disconnect-after SECONDS simulate losing the band mid-sync
      --live SECONDS             run the live feed and a heart-rate measurement first
      --diag PATH                also write the app's diagnostics log
      --sleep-report             print per-night sleep minutes after the sync

    Offline (stored data only, no band):
      --summary [YYYY-MM-DD]     daily metrics for the week ending that day
      --sleep-nights [YYYY-MM-DD] nights with sleep score and contributors

    Band checks:
      --hr                       heart-rate notifications follow streamsHeartRate

      -h, --help                 show this help
    """

/// Rejects unknown flags so a typo doesn't silently run a full sync.
func checkArguments(_ args: [String]) -> Bool {
    let needsValue: Set = ["--device", "--tz", "--health-start", "--disconnect-after", "--live", "--diag"]
    let optionalValue: Set = ["--summary", "--sleep-nights"]
    let switches: Set = ["--fresh", "--hr", "--sleep-report"]
    var rest = args.dropFirst()[...]
    while let arg = rest.popFirst() {
        if needsValue.contains(arg) {
            guard rest.popFirst() != nil else { return false }
        } else if optionalValue.contains(arg) {
            if let next = rest.first, !next.hasPrefix("--") { rest.removeFirst() }
        } else if !switches.contains(arg) {
            return false
        }
    }
    return true
}

@MainActor
func run() async throws {
    let args = CommandLine.arguments
    if args.contains("--help") || args.contains("-h") {
        print(usage)
        return
    }
    guard checkArguments(args) else {
        print(usage)
        exit(2)
    }
    func value(_ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    }

    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../").standardized
    let state = root.appendingPathComponent(".state")
    if args.contains("--fresh") { try? FileManager.default.removeItem(at: state) }
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)

    let deviceFile = root.appendingPathComponent("../ble-probe/.device").standardized
    let deviceString = value("--device") ?? (try? String(contentsOf: deviceFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let deviceString, let deviceID = UUID(uuidString: deviceString) else {
        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No device id (pass --device or run ble-probe scan)"])
    }
    let timeZone = value("--tz").flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent

    // Health start: set on the first run, like the app.
    let startFile = state.appendingPathComponent("health-start.txt")
    let healthStart: Date
    if let forced = value("--health-start").flatMap({ ISO8601DateFormatter().date(from: $0) }) {
        healthStart = forced
        try ISO8601DateFormatter().string(from: forced).write(to: startFile, atomically: true, encoding: .utf8)
    } else if let saved = try? String(contentsOf: startFile, encoding: .utf8), let date = ISO8601DateFormatter().date(from: saved) {
        healthStart = date
    } else {
        healthStart = .now
        try ISO8601DateFormatter().string(from: healthStart).write(to: startFile, atomically: true, encoding: .utf8)
    }

    let offsetFile = state.appendingPathComponent("band-clock-offset.txt")
    let previousOffset = (try? String(contentsOf: offsetFile, encoding: .utf8)).flatMap { Int($0) }

    let store = RecordStore(container: try RecordStore.container(url: state.appendingPathComponent("pulse.store")))
    // --summary: print the last 7 days from the tool's store and exit (no band needed).
    if args.contains("--summary") {
        let end = value("--summary").flatMap { ISO8601DateFormatter().date(from: $0 + "T12:00:00Z") } ?? .now
        let metrics = try SummaryService(store: store).load(days: 7, endingOn: end)
        func show(_ r: DayRange?) -> String { r.map { "\(Int($0.min))-\(Int($0.average.rounded()))-\(Int($0.max))" } ?? "-" }
        print("day         restingHR  HRV  HR min-avg-max  SpO2 min-avg-max  HR readings  steps  distance")
        for day in metrics.days {
            let label = day.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
            let rhr = metrics.restingHeartRate(on: day).map(String.init) ?? "-"
            let hrv = metrics.hrv(on: day).map(String.init) ?? "-"
            print("\(label)  \(rhr.padding(toLength: 9, withPad: " ", startingAt: 0))  \(hrv.padding(toLength: 3, withPad: " ", startingAt: 0))  \(show(metrics.value(.heartRate, on: day)).padding(toLength: 14, withPad: " ", startingAt: 0))  \(show(metrics.value(.spo2, on: day)).padding(toLength: 16, withPad: " ", startingAt: 0))  \(String(metrics.readings(.heartRate, on: day).count).padding(toLength: 11, withPad: " ", startingAt: 0))  \(metrics.stepsTotal(on: day))  \(metrics.distanceMeters(on: day)) m")
        }
        return
    }

    // --sleep-nights [YYYY-MM-DD]: the 14 nights ending on that day, with score and contributors.
    if args.contains("--sleep-nights") {
        let end = value("--sleep-nights").flatMap { ISO8601DateFormatter().date(from: $0 + "T12:00:00Z") } ?? .now
        let metrics = try SummaryService(store: store).load(days: 14, endingOn: end)
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        for value in metrics.sleepSeries() {
            let n = value.night
            let c = SleepScore.Contributor.allCases.map { "\($0.rawValue)=\(value.score.contributors[$0]!)" }.joined(separator: " ")
            print("\(value.day.formatted(.dateTime.day().month())): score \(value.score.value) (\(value.score.label))  \(time(n.fellAsleep))-\(time(n.wokeUp))  asleep \(n.asleep / 60)h\(String(format: "%02d", n.asleep % 60)) eff \(Int(n.efficiency * 100))% lat \(n.latency) wake-ups \(n.awakenings)")
            print("        \(c)")
        }
        return
    }

    let health = LedgerHealth(url: state.appendingPathComponent("health-ledger.json"))
    let engine = SyncEngine(store: store, health: health, reader: HistoryReader(timeZone: timeZone))

    let band = BandClient()
    band.pair(id: deviceID)
    print("Connecting to \(deviceID)  tz=\(timeZone.identifier)  healthStart=\(healthStart.formatted(date: .abbreviated, time: .standard))")
    let clock = ContinuousClock()
    let connectStart = clock.now
    try await band.connect()
    print("Connected in \(clock.now - connectStart)  serial=\(band.serial ?? "?")  battery=\(band.battery.map { "\($0)%" } ?? "?")")

    // --hr: check that heart-rate notifications follow streamsHeartRate (off 5 s, on 10 s, off 5 s).
    if args.contains("--hr") {
        var count = 0
        let started = Date()
        band.onHeartRate = { bpm in
            count += 1
            if count <= 3 || count % 10 == 0 { print(String(format: "    +%.1fs  %d bpm", Date().timeIntervalSince(started), bpm)) }
        }
        for (on, seconds) in [(false, 5.0), (true, 30.0), (false, 5.0)] {
            band.streamsHeartRate = on
            count = 0
            try await Task.sleep(for: .seconds(seconds))
            print("  heart rate \(on ? "on " : "off") for \(Int(seconds)) s: \(count) notifications")
        }
        band.disconnect()
        return
    }

    if let seconds = value("--disconnect-after").flatMap(Double.init) {
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            print("  !! simulating band loss after \(seconds)s")
            band.disconnect()
        }
    }

    // --live SECONDS: run the app's LiveFeed (and a 30 s heart-rate measurement), then sync.
    if let seconds = value("--live").flatMap(Double.init) {
        let live = LiveFeed()
        try await live.start(over: band)
        try await live.measure(.heartRate)
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try await Task.sleep(for: .seconds(5))
            let a = live.activity
            print("  live: steps=\(a?.steps ?? -1) dist=\(a?.distanceMeters ?? -1)m hr=\(a?.heartRate ?? -1) running=\(live.isRunning) measurement=\(live.measurement)")
        }
        await live.stop()
        print("  live stopped, syncing...")
    }

    let logURL = root.appendingPathComponent("../../logs/sync-\(Int(Date().timeIntervalSince1970)).jsonl").standardized
    // --diag PATH: also write the app's diagnostics log format (to check what users would send).
    let diagnostics = value("--diag").map { DiagnosticsLog(url: URL(fileURLWithPath: $0)) }
    let recorded: any CommandChannel = diagnostics.map { RecordingChannel(band, log: $0) } ?? band
    let channel = try LoggingChannel(recorded, logURL: logURL)
    let syncStart = clock.now
    defer { band.disconnect() }
    let report: SyncReport
    do {
        report = try await engine.sync(over: channel, serial: band.serial ?? "unknown", healthStart: healthStart,
                                       bandClockOffset: previousOffset)
        try String(report.bandClockOffset).write(to: offsetFile, atomically: true, encoding: .utf8)
    } catch {
        channel.finish()
        print("SYNC FAILED after \(clock.now - syncStart): \(error.localizedDescription)")
        throw error
    }
    channel.finish()

    print("\nSync finished in \(clock.now - syncStart)  (log: \(logURL.path))")
    print("  band clock offset: read with \(previousOffset.map { "\($0 / 3600)h" } ?? "phone zone"), set to \(report.bandClockOffset / 3600)h")
    for kind in HistoryKind.syncOrder {
        let status = report.failures[kind].map { "FAILED: \($0)" } ?? "+\(report.newRecords[kind] ?? 0) new"
        print("  \(kind)".padding(toLength: 16, withPad: " ", startingAt: 0) + status)
    }
    print("  dropped records: \(report.dropped)")
    print("  Health: \(report.exportedSamples) samples this run  (new \(health.new), replaced \(health.replaced), repeated \(health.repeated); ledger total \(health.total))")
    if !health.byMetric.isEmpty {
        print("          by metric: " + health.byMetric.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " "))
    }
    if let error = report.exportError { print("  Health error: \(error)") }
    for night in health.sleepMinutes.keys.sorted().suffix(args.contains("--sleep-report") ? 400 : 0) {
        let m = health.sleepMinutes[night]!
        print("  sleep \(night): awake \(m[.awake] ?? 0)  REM \(m[.rem] ?? 0)  core \(m[.core] ?? 0)  deep \(m[.deep] ?? 0) min")
    }
    // Newest records: raw band time (BCD hh:mm:ss) next to the absolute time they were stored under.
    for kind in [HistoryKind.spotHR, .spo2] {
        let raw = Int(kind.rawValue)
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.kindRaw == raw }, sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 4
        let rows = try store.container.mainContext.fetch(descriptor).map { r in
            let b = [UInt8](r.raw)
            return String(format: "band %02x:%02x:%02x -> %@", b[6], b[7], b[8], r.start.formatted(date: .omitted, time: .standard))
        }
        print("  newest \(kind): " + rows.joined(separator: " | "))
    }
    print("  now: \(Date().formatted(date: .omitted, time: .standard))")
}

do {
    try await run()
} catch {
    print("FAILED: \(error.localizedDescription)")
    exit(1)
}
