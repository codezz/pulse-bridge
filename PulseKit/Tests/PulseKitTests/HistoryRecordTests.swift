import Foundation
import Testing
@testable import PulseKit

struct HistoryRecordTests {
    private func record(_ kind: HistoryKind, _ hex: String) throws -> HistoryRecord {
        try #require(HistoryRecord(kind: kind, raw: bytes(hex), timeZone: utc))
    }

    @Test func historyCommand() {
        #expect(Command.history(.spotHR, mode: .next) == bytes("55 02 00 00 00 00 00 00 00 00 00 00 00 00 00 57"))
    }

    @Test func dailyTotals() throws {
        let r = try record(.dailyTotals, "51 0b 26 03 20 bc 0a 00 00 bd 04 00 00 c3 00 00 00 ce 51 02 00 1b 34 00 00 00 00")
        #expect(r.start == utcDate(2026, 3, 20))
        #expect(r.reading == .dailyTotals(steps: 2748, distanceMeters: 1950))
    }

    @Test func activityDetail() throws {
        let r = try record(.activity, "52 07 00 26 03 20 19 29 46 82 00 a2 06 08 00 44 00 00 00 2f 0f 00 00 00 00")
        #expect(r.start == utcDate(2026, 3, 20, 19, 29, 46))
        #expect(r.reading == .activity(steps: 130, distanceMeters: 80, minuteSteps: [68, 0, 0, 0, 47, 15, 0, 0, 0, 0]))
    }

    @Test func sleep() throws {
        let r = try #require(HistoryRecord(kind: .sleep, raw: padded("53 00 00 26 03 27 05 09 03 03 03 02 01", to: 130), timeZone: utc))
        #expect(r.start == utcDate(2026, 3, 27, 5, 9, 3))
        #expect(r.reading == .sleep(minuteStages: [3, 2, 1]))
    }

    @Test func continuousHeartRate() throws {
        let r = try record(.continuousHR, "54 00 00 26 06 16 11 15 59 4a 5b 00 00 00 00 00 00 00 00 00 00 00 00 00")
        #expect(r.start == utcDate(2026, 6, 16, 11, 15, 59))
        #expect(r.reading == .continuousHR(minuteBPM: [74, 91] + Array(repeating: 0, count: 13)))
    }

    @Test func spotHeartRate() throws {
        let r = try record(.spotHR, "55 00 00 26 06 16 18 06 14 47")
        #expect(r.start == utcDate(2026, 6, 16, 18, 6, 14))
        #expect(r.reading == .spotHR(bpm: 71))
    }

    @Test func hrv() throws {
        let r = try record(.hrv, "56 00 00 26 03 27 05 14 22 31 2f 4a 2f 76 4b")
        #expect(r.reading == .hrv(ms: 49, heartRate: 74, stress: 47, systolic: 118, diastolic: 75))
    }

    @Test func bloodOxygen() throws {
        let r = try record(.spo2, "66 00 00 26 06 16 13 42 00 62")
        #expect(r.start == utcDate(2026, 6, 16, 13, 42, 0))
        #expect(r.reading == .spo2(percent: 98))
    }

    @Test func rejectsWrongSizeOpcodeOrDate() {
        #expect(HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 06 16 18 06 14"), timeZone: utc) == nil)
        #expect(HistoryRecord(kind: .spotHR, raw: bytes("66 00 00 26 06 16 18 06 14 47"), timeZone: utc) == nil)
        #expect(HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 1a 16 18 06 14 47"), timeZone: utc) == nil)
    }
}
