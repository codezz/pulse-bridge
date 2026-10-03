import Foundation
import Testing
@testable import PulseKit

struct WorkoutTests {
    /// Captured 2026-10-03: 3 Feb 06:17:26, mode 9, HR 126, 569 s, 970 steps, 73 kcal, about 0.84 km.
    let captured = bytes("5c 00 00 26 02 03 06 17 26 09 7e 39 02 ca 03 0b 14 00 00 92 42 a2 1f 56 3f")
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    @Test func historyKind() {
        #expect(HistoryKind.workout.rawValue == 0x5C)
        #expect(HistoryKind.workout.recordSize == 25)
        #expect(HistoryKind.syncOrder.contains(.workout))
        #expect(HistoryKind.workout.exportsToHealth)
    }

    @Test func parsesTheCapturedWorkout() throws {
        let r = try #require(HistoryRecord(kind: .workout, raw: captured, timeZone: utc))
        #expect(r.start == utcDate(2026, 2, 3, 6, 17, 26))
        guard case let .workout(info) = r.reading else { Issue.record("not a workout"); return }
        #expect(info.activity == .walking)
        #expect(info.heartRate == 126)
        #expect(info.seconds == 569)
        #expect(info.steps == 970)
        #expect(info.calories == 73)
        #expect(info.distanceMeters == 836)
    }

    @Test func activityTypes() {
        #expect(WorkoutActivity(bandMode: 9) == .walking)
        #expect(WorkoutActivity(bandMode: 0) == .running)
        #expect(WorkoutActivity(bandMode: 1) == .cycling)
        #expect(WorkoutActivity(bandMode: 42) == .other)
    }

    @Test func becomesOneHealthWorkout() throws {
        let r = try #require(HistoryRecord(kind: .workout, raw: captured, timeZone: utc))
        let samples = r.healthSamples(id: "X")
        #expect(samples.count == 1)
        let s = try #require(samples.first)
        #expect(s.metric == .workout)
        #expect(s.start == r.start)
        #expect(s.end == r.start + 569)
        #expect(s.syncID == "X")
        #expect(s.workout?.steps == 970)
    }

    @Test func zeroLengthWorkoutsAreSkipped() throws {
        let empty = makeRecord(.workout, utcDate(2026, 2, 3, 6), [9, 0, 0, 0])
        #expect(empty.healthSamples(id: "X").isEmpty)
    }

    @Test func dailyMetricsListWorkoutsNewestFirst() {
        let day = utcDate(2026, 2, 3)
        let records = [makeRecord(.workout, day + 3600, [9, 100, 60, 0, 10, 0]),
                       makeRecord(.workout, day + 7200, [9, 110, 120, 0, 20, 0]),
                       makeRecord(.workout, day + 86400 + 60, [9, 90, 60, 0, 5, 0])]
        let m = DailyMetrics(readings: Readings(records: records), days: [day], calendar: calendar)
        #expect(m.workouts(on: day).map(\.start) == [day + 7200, day + 3600])
        #expect(m.workouts().map(\.start) == [day + 7200, day + 3600])
    }

    @Test func corruptFloatsDontCrash() throws {
        // Review finding: NaN/infinite calories or distance trapped on Int conversion, on every launch.
        let corrupt = bytes("5c 00 00 26 02 03 06 17 26 09 7e 39 02 ca 03 0b 14 ff ff ff ff ff ff 80 7f")
        let r = try #require(HistoryRecord(kind: .workout, raw: corrupt, timeZone: utc))
        guard case let .workout(info) = r.reading else { Issue.record("not a workout"); return }
        #expect(info.calories == 0)
        #expect(info.distanceMeters == 0)
    }
}
