import Foundation
import Testing
@testable import PulseKit

struct HealthSampleTests {
    private func record(_ kind: HistoryKind, _ hex: String) throws -> HistoryRecord {
        try #require(HistoryRecord(kind: kind, raw: bytes(hex), timeZone: utc))
    }

    @Test func idUsesRawTimestamp() throws {
        let r = try record(.spotHR, "55 00 00 26 06 16 18 06 14 47")
        #expect(r.id(serial: "WS01A-01-00000") == "WS01A-01-00000.55.260616180614")
    }

    @Test func idIgnoresTimeZone() throws {
        let raw = bytes("55 00 00 26 06 16 18 06 14 47")
        let a = try #require(HistoryRecord(kind: .spotHR, raw: raw, timeZone: utc))
        let b = try #require(HistoryRecord(kind: .spotHR, raw: raw, timeZone: TimeZone(identifier: "Europe/Bucharest")!))
        #expect(a.start != b.start)
        #expect(a.id(serial: "S") == b.id(serial: "S"))
    }

    @Test func activityBecomesMinuteStepsPlusDistance() throws {
        let r = try record(.activity, "52 00 00 26 06 16 13 33 58 5d 00 7a 3b 06 00 3c 21 00 00 00 00 00 00 00 00")
        let t0 = utcDate(2026, 6, 16, 13, 33, 58)
        #expect(r.healthSamples(id: "X") == [
            HealthSample(metric: .steps, start: t0, end: t0 + 60, value: 60, syncID: "X.0"),
            HealthSample(metric: .steps, start: t0 + 60, end: t0 + 120, value: 33, syncID: "X.1"),
            HealthSample(metric: .distance, start: t0, end: t0 + 600, value: 60, syncID: "X.d"),
        ])
    }

    @Test func continuousHeartRateSkipsEmptyMinutes() throws {
        let r = try record(.continuousHR, "54 00 00 26 06 16 11 15 59 4a 5b 00 00 00 00 00 00 00 00 00 00 00 00 00")
        let t0 = utcDate(2026, 6, 16, 11, 15, 59)
        #expect(r.healthSamples(id: "X") == [
            HealthSample(metric: .heartRate, start: t0, end: t0, value: 74, syncID: "X.0"),
            HealthSample(metric: .heartRate, start: t0 + 60, end: t0 + 60, value: 91, syncID: "X.1"),
        ])
    }

    @Test func pointSamples() throws {
        let hr = try record(.spotHR, "55 00 00 26 06 16 18 06 14 47")
        #expect(hr.healthSamples(id: "X").map(\.value) == [71])
        let hrv = try record(.hrv, "56 00 00 26 03 27 05 14 22 31 2f 4a 2f 76 4b")
        #expect(hrv.healthSamples(id: "X") == [HealthSample(metric: .hrv, start: hrv.start, end: hrv.start, value: 49, syncID: "X")])
        let spo2 = try record(.spo2, "66 00 00 26 06 16 13 42 00 62")
        #expect(spo2.healthSamples(id: "X").map(\.value) == [0.98])
    }

    @Test func failedMeasurementsAreSkipped() throws {
        #expect(try record(.spotHR, "55 02 00 26 06 16 17 27 40 00").healthSamples(id: "X").isEmpty)
    }

    @Test func localOnlyKindsExportNothing() throws {
        let daily = try record(.dailyTotals, "51 00 26 06 16 71 00 00 00 41 00 00 00 07 00 00 00 43 77 01 00 01 36 00 00 00 00")
        #expect(daily.healthSamples(id: "X").isEmpty)
        #expect(!HistoryKind.dailyTotals.exportsToHealth)
        #expect(HistoryKind.sleep.exportsToHealth)
        #expect(HistoryKind.activity.exportsToHealth)
    }

    @Test func sleepBecomesOneSamplePerStageRun() throws {
        // 5 5 = falling asleep, 2 2 = core, 3 = deep, 1 = REM (mapping in docs/protocol.md)
        let r = try #require(HistoryRecord(kind: .sleep, raw: padded("53 00 00 26 03 27 05 09 00 06 05 05 02 02 03 01", to: 130), timeZone: utc))
        let t0 = utcDate(2026, 3, 27, 5, 9, 0)
        func sample(_ stage: SleepStage, _ from: Int, _ to: Int) -> HealthSample {
            HealthSample(metric: .sleep, start: t0 + Double(from * 60), end: t0 + Double(to * 60), value: Double(stage.rawValue), syncID: "X.\(from)")
        }
        #expect(r.healthSamples(id: "X") == [sample(.awake, 0, 2), sample(.core, 2, 4), sample(.deep, 4, 5), sample(.rem, 5, 6)])
    }

    @Test func unknownSleepValuesAreSkipped() throws {
        let r = try #require(HistoryRecord(kind: .sleep, raw: padded("53 00 00 26 03 27 05 09 00 04 09 02 02 1e", to: 130), timeZone: utc))
        #expect(r.healthSamples(id: "X").map(\.syncID) == ["X.1"])
    }

    @Test func bandSleepValueMapping() {
        #expect([1, 2, 3, 4, 5, 9].map(SleepStage.init(bandValue:)) == [.rem, .core, .deep, .awake, .awake, nil])
    }

    @Test func emptySleepRecordExportsNothing() throws {
        let r = try #require(HistoryRecord(kind: .sleep, raw: padded("53 00 00 26 03 27 05 09 00 00", to: 130), timeZone: utc))
        #expect(r.healthSamples(id: "X").isEmpty)
    }
}
