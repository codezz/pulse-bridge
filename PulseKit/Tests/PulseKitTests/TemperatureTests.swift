import Foundation
import Testing
@testable import PulseKit

struct TemperatureTests {
    @Test func decodesARecord() throws {
        // Captured 2026-10-05 (`65 00` read): record 0x0370, 2026-02-02 06:10, 0x0166 = 35.8 °C
        let r = try #require(HistoryRecord(kind: .temperature, raw: bytes("65 70 03 26 02 02 06 10 00 66 01"), timeZone: utc))
        #expect(r.start == utcDate(2026, 2, 2, 6, 10))
        #expect(r.reading == .temperature(celsius: 35.8))
        #expect(HistoryKind.temperature.recordSize == 11)
    }

    @Test func syncedButNotSentToHealth() throws {
        #expect(HistoryKind.syncOrder.contains(.temperature))
        #expect(!HistoryKind.temperature.exportsToHealth)
        let r = try #require(HistoryRecord(kind: .temperature, raw: bytes("65 70 03 26 02 02 06 10 00 66 01"), timeZone: utc))
        #expect(r.healthSamples(id: "X").isEmpty)
    }

    @Test func implausibleValuesAreDropped() throws {
        let ok = try #require(HistoryRecord(kind: .temperature, raw: bytes("65 70 03 26 02 02 06 10 00 66 01"), timeZone: utc))
        let hot = try #require(HistoryRecord(kind: .temperature, raw: bytes("65 71 03 26 02 02 06 20 00 a4 01"), timeZone: utc))  // 42.0
        #expect(Readings(records: [ok, hot]).temperature.map(\.value) == [35.8])
    }

    /// Without sleep data the night temperature still shows (whole night window), but it stays out of
    /// the per-night series that baselines, highlights and readiness use: evening and morning wrist
    /// readings would pull the usual down.
    @Test func nightsWithoutSleepStayOutOfTheBaseline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let record = try #require(HistoryRecord(kind: .temperature, raw: bytes("65 70 03 26 02 02 02 10 00 66 01"), timeZone: utc))
        let day = utcDate(2026, 2, 2)
        let metrics = DailyMetrics(readings: Readings(records: [record]), days: [day], calendar: calendar)
        #expect(metrics.nightTemperature(on: day) == 35.8)
        #expect(metrics.insightSeries()[.temperature] == nil)
    }

    /// Deleting history (mode 99) can't be built for any history opcode, alarms or temperature.
    @Test func deleteModesCantBeBuilt() async {
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x65, 0x99]) }
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x57, 0x99]) }
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x53, 0x99]) }
    }


    /// Frame.make refuses whatever this flags (its precondition); `5C 09` deletes workouts.
    @Test func deleteDetection() {
        #expect(Frame.isDelete([0x5C, 0x09]))
        #expect(Frame.isDelete([0x65, 0x99]))
        #expect(!Frame.isDelete([0x09, 0x01]))
        #expect(!Frame.isDelete([0x52, 0x02]))
    }

    @Test func readsAreStillAllowed() {
        #expect(Frame.make([0x65, 0x00]).count == 16)
        #expect(Frame.make([0x57, 0x00]).count == 16)
    }
}
