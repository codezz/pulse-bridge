import Foundation
import Testing
@testable import PulseKit

@MainActor
struct RecordStoreTests {
    let store: RecordStore

    init() throws {
        store = RecordStore(container: try RecordStore.container(inMemory: true))
    }

    private func spot(_ minute: Int) -> HistoryRecord {
        HistoryRecord(kind: .spotHR, raw: spotHR(minute: minute), timeZone: utc)!
    }

    @Test func insertSkipsRecordsAlreadyStored() throws {
        #expect(try store.insert([spot(1), spot(2)], serial: "S") == 2)
        #expect(try store.insert([spot(2), spot(3)], serial: "S") == 1)
    }

    @Test func latestStartIsPerKind() throws {
        try store.insert([spot(5), spot(9)], serial: "S")
        #expect(try store.latestStart(of: .spotHR) == utcDate(2026, 6, 16, 10, 9))
        #expect(try store.latestStart(of: .spo2) == nil)
    }

    @Test func exportQueue() throws {
        let daily = HistoryRecord(kind: .dailyTotals, raw: bytes("51 00 26 06 16 71 00 00 00 41 00 00 00 07 00 00 00 43 77 01 00 01 36 00 00 00 00"), timeZone: utc)!
        try store.insert([spot(1), daily], serial: "S")
        let pending = try store.pendingExport()
        #expect(pending.map(\.historyRecord) == [Optional(spot(1))])
        try store.markExported(pending)
        #expect(try store.pendingExport().isEmpty)
    }

    @Test func changedRecordIsRequeuedWithHigherVersion() throws {
        try store.insert([spot(1)], serial: "S")
        try store.markExported(try store.pendingExport())
        let changed = HistoryRecord(kind: .spotHR, raw: spotHR(minute: 1, bpm: 80), timeZone: utc)!
        #expect(try store.insert([changed], serial: "S") == 0)
        let pending = try store.pendingExport()
        #expect(pending.map(\.version) == [2])
        #expect(pending.first?.historyRecord == changed)
    }

    @Test func recordsBeforeHealthStartAreNotQueued() throws {
        try store.insert([spot(1), spot(9)], serial: "S", healthStart: utcDate(2026, 6, 16, 10, 5))
        #expect(try store.pendingExport().map(\.start) == [utcDate(2026, 6, 16, 10, 9)])
        #expect(try store.latestStart(of: .spotHR) == utcDate(2026, 6, 16, 10, 9))
    }

    @Test func fileStoreKeepsRecordsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        try RecordStore(container: try RecordStore.container(url: url)).insert([spot(1)], serial: "S")
        let reopened = RecordStore(container: try RecordStore.container(url: url))
        #expect(try reopened.latestStart(of: .spotHR) == utcDate(2026, 6, 16, 10, 1))
    }

    @Test func storedRecordWithAWrongSizeIsSkipped() throws {
        try store.insert([spot(1)], serial: "S")
        let stored = try store.pendingExport()[0]
        stored.raw = Data([0x55, 0x00])                                   // truncated on disk
        #expect(stored.historyRecord == nil)
    }

    @Test func repeatedClockHourKeepsBothRecords() throws {
        // Review finding: after the autumn clock change the band stamps 07:00-08:00 twice.
        let bucharest = TimeZone(identifier: "Europe/Bucharest")!
        let summer = HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 10 25 07 30 00 46"), timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)!
        let winter = HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 10 25 07 30 00 50"), timeZone: TimeZone(secondsFromGMT: 2 * 3600)!)!
        #expect(try store.insert([summer], serial: "S") == 1)
        #expect(try store.insert([winter], serial: "S") == 1)
        #expect(try store.records(of: [.spotHR], from: .distantPast, to: .distantFuture).count == 2)
        _ = bucharest
    }

    @Test func reReadingInAnotherOffsetIsNotANewRecord() throws {
        let raw = bytes("55 00 00 26 10 25 07 30 00 46")
        try store.insert([HistoryRecord(kind: .spotHR, raw: raw, timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)!], serial: "S")
        #expect(try store.insert([HistoryRecord(kind: .spotHR, raw: raw, timeZone: TimeZone(secondsFromGMT: 2 * 3600)!)!], serial: "S") == 0)
    }

    @Test func shiftedIndexIsNotAChange() throws {
        // Found while fixing the above: the band's record index shifts as new records arrive, so every
        // re-read looked "changed" and was re-exported to Health with a new version.
        try store.insert([spot(1)], serial: "S")
        try store.markExported(try store.pendingExport())
        var raw = [UInt8](spotHR(minute: 1)); raw[1] = 7                       // same record, index 7
        try store.insert([HistoryRecord(kind: .spotHR, raw: Data(raw), timeZone: utc)!], serial: "S")
        #expect(try store.pendingExport().isEmpty)
    }
}

