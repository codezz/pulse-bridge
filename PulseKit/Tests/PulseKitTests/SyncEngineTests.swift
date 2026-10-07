import Foundation
import Testing
@testable import PulseKit

@MainActor
struct SyncEngineTests {
    static let now = utcDate(2026, 10, 2, 16, 49, 54)
    static let band: [HistoryKind: [Data]] = [
        .activity: [bytes("52 00 00 26 06 16 13 33 58 5d 00 7a 3b 06 00 3c 21 00 00 00 00 00 00 00 00")],
        .spotHR: [bytes("55 00 00 26 06 16 18 06 14 47")],
        .spo2: [bytes("66 00 00 26 06 16 13 42 00 62")],
    ]

    let store: RecordStore
    let health = FakeHealth()
    let engine: SyncEngine

    init() throws {
        store = RecordStore(container: try RecordStore.container(inMemory: true))
        engine = SyncEngine(store: store, health: health, reader: HistoryReader(timeZone: utc), now: { Self.now })
    }

    @Test func setsTimeThenStoresAndExports() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(channel.sent.first == bytes("01 26 10 02 16 49 54 00 00 00 00 00 00 00 00 ec"))
        #expect(report.newRecords[.activity] == 1)
        #expect(report.newRecords[.spotHR] == 1)
        #expect(report.newRecords[.spo2] == 1)
        #expect(report.failures.isEmpty)
        #expect(report.exportedSamples == 6) // 2 step minutes + 2 distance minutes + HR + SpO2
        #expect(health.saved.count == 6)
        #expect(try store.pendingExport().isEmpty)
    }

    @Test func secondSyncAddsNothing() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        _ = try await engine.sync(over: channel, serial: "S")
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(report.newRecords.values.allSatisfy { $0 == 0 })
        #expect(health.saved.count == 6)
    }

    @Test func failingKindDoesNotStopOthers() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band, silent: [.hrv]))
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(report.failures[.hrv] != nil)
        #expect(report.newRecords[.spo2] == 1)
    }

    /// The diagnostics log gets the error by name, whatever language the screen shows it in.
    @Test func failureKeepsAnEnglishLogText() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band, silent: [.hrv]))
        let report = try await engine.sync(over: channel, serial: "S")
        let failure = try #require(report.failures[.hrv])
        #expect(failure.log.hasPrefix("noResponse("))
        #expect(failure.message == PulseError.noResponse(HistoryKind.hrv.rawValue).localizedDescription)
    }

    @Test func deniedMetricStaysPendingUntilAllowed() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        health.denied = [.heartRate]
        let first = try await engine.sync(over: channel, serial: "S")
        #expect(first.notAllowed == [.heartRate])
        #expect(try store.pendingExport().map(\.kindRaw) == [Int(HistoryKind.spotHR.rawValue)])

        health.denied = []
        _ = try await engine.sync(over: channel, serial: "S")
        #expect(health.saved.contains { $0.metric == .heartRate && $0.value == 71 })
        #expect(try store.pendingExport().isEmpty)
    }

    @Test func disconnectKeepsFinishedKinds() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        channel.disconnectAfter = 3 // set-time ack, activity record, activity end marker
        await #expect(throws: PulseError.notConnected) {
            try await engine.sync(over: channel, serial: "S")
        }
        #expect(try store.latestStart(of: .activity) != nil)
        #expect(try store.latestStart(of: .continuousHR) == nil)
    }

    @Test func futureRecordsAreDropped() async throws {
        let future = bytes("55 00 00 27 01 01 10 00 00 47")
        let channel = FakeChannel(respond: bandResponder([.spotHR: [future]]))
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(report.newRecords[.spotHR] == 0)
        #expect(report.dropped == 1)
        #expect(try store.latestStart(of: .spotHR) == nil)
    }

    @Test func concurrentSyncIsRejected() async throws {
        let channel = GatedChannel()
        let first = Task { try await engine.sync(over: channel, serial: "S") }
        while channel.gate == nil { await Task.yield() }
        await #expect(throws: PulseError.busy) {
            try await engine.sync(over: channel, serial: "S")
        }
        channel.gate?.resume()
        _ = try? await first.value
    }

    @Test func setTimeIsRetriedWhenTheBandIgnoresIt() async throws {
        // Real band: right after a reconnect it ignored the first set-time (log 2026-10-02 17:53).
        var setTimeCalls = 0
        let normal = bandResponder(Self.band)
        let channel = FakeChannel { frame in
            guard frame.first == Opcode.setTime else { return normal(frame) }
            setTimeCalls += 1
            return setTimeCalls == 1 ? [] : normal(frame)
        }
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(setTimeCalls == 2)
        #expect(report.newRecords[.spotHR] == 1)
    }

    @Test func missingSetTimeAckFailsTheSync() async {
        let channel = FakeChannel()
        await #expect(throws: PulseError.noResponse(Opcode.setTime)) {
            try await engine.sync(over: channel, serial: "S")
        }
    }

    @Test func rereadsTheLastDayToCatchClockShifts() async throws {
        let known = bytes("55 00 00 26 06 16 18 06 14 47")
        let channel = FakeChannel(respond: bandResponder([.spotHR: [known]]))
        _ = try await engine.sync(over: channel, serial: "S")
        // After flying east (or a DST fall-back), newer band records parse as earlier than the cursor.
        channel.respond = bandResponder([.spotHR: [known, bytes("55 01 00 26 06 16 16 30 00 48")]])
        let report = try await engine.sync(over: channel, serial: "S")
        #expect(report.newRecords[.spotHR] == 1)
    }

    @Test func growingActivityBlockIsReexported() async throws {
        let partial = bytes("52 00 00 26 06 16 13 33 58 3c 00 7a 3b 06 00 3c 00 00 00 00 00 00 00 00 00")
        let full = bytes("52 00 00 26 06 16 13 33 58 5d 00 7a 3b 06 00 3c 21 00 00 00 00 00 00 00 00")
        let channel = FakeChannel(respond: bandResponder([.activity: [partial]]))
        _ = try await engine.sync(over: channel, serial: "S")
        channel.respond = bandResponder([.activity: [full]])
        _ = try await engine.sync(over: channel, serial: "S")
        #expect(health.saved.filter { $0.metric == .steps && $0.syncID.hasSuffix(".1") }.map(\.value) == [33])
        #expect(health.saved.last { $0.metric == .distance }?.version == 2)
    }

    @Test func historyBeforeHealthStartStaysOnThePhone() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        // Activity 13:33 and SpO2 13:42 are older than the cutoff; spot HR 18:06 is newer.
        let report = try await engine.sync(over: channel, serial: "S", healthStart: utcDate(2026, 6, 16, 14, 0))
        #expect(report.newRecords[.activity] == 1)
        #expect(report.newRecords[.spo2] == 1)
        #expect(health.saved.map(\.metric) == [.heartRate])
        #expect(try store.pendingExport().isEmpty)
    }

    @Test func recordsAreReadInTheOffsetTheBandClockWasSetTo() async throws {
        // Band clock was set in Dubai (UTC+4); the phone is now in UTC. Seen on the real band 2026-10-02.
        let channel = FakeChannel(respond: bandResponder([.spotHR: [bytes("55 00 00 26 06 16 18 06 14 47")]]))
        let report = try await engine.sync(over: channel, serial: "S", bandClockOffset: 4 * 3600)
        #expect(try store.latestStart(of: .spotHR) == utcDate(2026, 6, 16, 14, 6, 14))
        #expect(report.bandClockOffset == 0)
    }

    @Test func reportedOffsetFollowsDaylightSaving() async throws {
        let bucharest = TimeZone(identifier: "Europe/Bucharest")!
        func offset(at date: Date) async throws -> Int {
            let engine = SyncEngine(store: store, health: health, reader: HistoryReader(timeZone: bucharest), now: { date })
            return try await engine.sync(over: FakeChannel(respond: bandResponder([:])), serial: "S").bandClockOffset
        }
        #expect(try await offset(at: utcDate(2026, 10, 2, 12)) == 3 * 3600)
        #expect(try await offset(at: utcDate(2026, 11, 2, 12)) == 2 * 3600)
    }

    @Test func bandOnlySyncStoresWithoutExportingUntilTheNextFullSync() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        let bandOnly = try await engine.sync(over: channel, serial: "S", exportToHealth: false)
        #expect(bandOnly.newRecords[.spotHR] == 1)
        #expect(!bandOnly.exportedToHealth)
        #expect(health.saved.isEmpty)
        #expect(try store.pendingExport().count == 3)

        let full = try await engine.sync(over: channel, serial: "S")
        #expect(full.exportedToHealth)
        #expect(full.exportedSamples == 6)
        #expect(try store.pendingExport().isEmpty)
    }

    @Test func manualHealthExportWritesWhatIsWaitingWithoutTheBand() async throws {
        let channel = FakeChannel(respond: bandResponder(Self.band))
        _ = try await engine.sync(over: channel, serial: "S", exportToHealth: false)
        let sentBefore = channel.sent.count
        let report = await engine.exportToHealth()
        #expect(report.exportedToHealth)
        #expect(report.exportedSamples == 6)
        #expect(health.saved.count == 6)
        #expect(try store.pendingExport().isEmpty)
        #expect(channel.sent.count == sentBefore) // no band traffic
    }

    @Test func aFutureRecordDoesntHideNewerRealOnes() async throws {
        // 23 h ahead is allowed in; the cursor must still not move past now.
        let future = HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 10 03 15 49 00 46"), timeZone: utc)!  // now + 23 h
        try store.insert([future], serial: "S")
        let older = bytes("55 01 00 26 10 02 13 19 00 48")                                          // now - 3.5 h
        let report = try await engine.sync(over: FakeChannel(respond: bandResponder([.spotHR: [older]])), serial: "S")
        #expect(report.newRecords[.spotHR] == 1)
    }

    @Test func bandClockOffsetIsReportedEvenIfTheSyncFails() async throws {
        var offsets: [Int] = []
        engine.onBandClockSet = { offsets.append($0) }
        let channel = FakeChannel(respond: bandResponder(Self.band))
        channel.disconnectAfter = 1
        await #expect(throws: PulseError.notConnected) { try await engine.sync(over: channel, serial: "S") }
        #expect(offsets == [0])
    }
}
