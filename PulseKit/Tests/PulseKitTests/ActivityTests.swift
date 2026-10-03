import Foundation
import Testing
@testable import PulseKit

struct FrameAndPacketTests {
    @Test func vibrateAndProfileFrames() {
        // Captured writes 2026-10-03
        #expect(Command.vibrate(times: 5) == bytes("36 05 00 00 00 00 00 00 00 00 00 00 00 00 00 3b"))
        #expect(Command.readProfile == Frame.make([0x42]))
    }

    @Test func profileFromAndToTheBand() throws {
        let now = utcDate(2026, 10, 3)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        // Layout of a captured packet; the values are made up.
        let p = try #require(UserProfile(bandPacket: bytes("42 01 23 aa 46 3e 38 38 38 38 38 38 00 00 00 e4"), now: now, calendar: calendar))
        #expect(p == UserProfile(birthYear: 1991, sex: .male, heightCm: 170, weightKg: 70, stepLengthCm: 62))
        #expect(p.age(at: now, calendar: calendar) == 35)
        #expect(p.command(at: now, calendar: calendar) == Frame.make([0x02, 1, 0x23, 0xaa, 0x46, 0x3e]))
        #expect(UserProfile(bandPacket: bytes("41 00"), now: now, calendar: calendar) == nil)
    }
}

struct ZoneTests {
    let t0 = utcDate(2026, 10, 3, 9)

    @Test func karvonenBounds() {
        let z = HeartRateZones(max: 179, resting: 59)                  // reserve 120
        #expect((1...5).map { z.lowerBound(of: $0) } == [119, 131, 143, 155, 167])
        #expect(z.range(of: 2) == 131...142)
        #expect(z.range(of: 5) == 167...179)
        #expect([118, 119, 142, 143, 200].map { z.zone(for: $0) } == [0, 1, 2, 3, 5])
    }

    @Test func tanaka() {
        #expect(HeartRateProfile.tanaka(age: 42) == 179)
    }

    @Test func twoSpikesDontCount() {
        let readings = [Reading(date: t0, value: 185), Reading(date: t0 + 30, value: 186), Reading(date: t0 + 60, value: 140)]
        #expect(HeartRateProfile.sustainedMax(readings, since: t0 - 86400) == 140)
        let p = HeartRateProfile(age: 42, heartRate: readings, nightlyResting: [], now: t0)
        #expect(p.max == 179 && p.maxSource == .age)
    }

    @Test func sustainedEffortRaisesMax() {
        let readings = [Reading(date: t0, value: 185), Reading(date: t0 + 60, value: 186), Reading(date: t0 + 120, value: 184)]
        let p = HeartRateProfile(age: 42, heartRate: readings, nightlyResting: [], now: t0)
        #expect(p.max == 184 && p.maxSource == .measured)
    }

    @Test func oldPeaksExpire() {
        let old = t0 - 181 * 86400
        let readings = [Reading(date: old, value: 190), Reading(date: old + 60, value: 190), Reading(date: old + 120, value: 190)]
        #expect(HeartRateProfile(age: 42, heartRate: readings, nightlyResting: [], now: t0).maxSource == .age)
    }

    @Test func secondBySecondSpikesDontSetMax() {
        // Review finding: 1 Hz activity data let a 3-second artifact through.
        let run = (0..<180).map { Reading(date: t0 + Double($0), value: $0 % 60 < 3 ? 205 : 150) }
        let minutes = HeartRateProfile.minuteMedians(run)
        #expect(minutes.count == 3 && minutes.allSatisfy { $0.value == 150 })
        #expect(HeartRateProfile(age: 42, heartRate: minutes, nightlyResting: [], now: t0 + 180).max == 179)
    }

    @Test func restingIsTheMedianOrADefault() {
        #expect(HeartRateProfile(age: 42, heartRate: [], nightlyResting: [58, 62, 59, 70], now: t0).resting == 60)
        let fallback = HeartRateProfile(age: 42, heartRate: [], nightlyResting: [55, 56], now: t0)
        #expect(fallback.resting == 60 && fallback.restingIsDefault)
        #expect(HeartRateProfile(age: 42, heartRate: [], nightlyResting: [55, 57, 59], now: t0).zones == HeartRateZones(max: 179, resting: 57))
    }
}

struct ActivityRecorderTests {
    let t0 = utcDate(2026, 10, 3, 7)
    let zones = HeartRateZones(max: 179, resting: 59)

    /// A point `step` steps north of 45.0 N, 0.0005 degrees (about 55.6 m) per step, 10 s apart.
    private func point(_ step: Int, accuracy: Double = 5, at offset: TimeInterval? = nil) -> GeoPoint {
        GeoPoint(date: t0 + (offset ?? Double(step) * 10), latitude: 45 + Double(step) * 0.0005, longitude: 0, accuracy: accuracy)
    }

    private func recorder() -> ActivityRecorder {
        ActivityRecorder(activity: .running, targetZone: 2, zones: zones, start: t0)
    }

    @Test func distanceAndSplits() {
        var r = recorder()
        for step in 0...20 { r.add(point(step)) }
        #expect(abs(r.distance - 1112) < 2)
        #expect(r.splits == [180])                                  // the 18th step crosses 1 km at t0 + 180
        #expect(abs(r.averagePace(at: t0 + 200)! - 200 / 1.112) < 1)
        #expect(abs(r.currentPace(at: t0 + 200)! - 30 / 0.1668) < 1)  // 3 steps in the last 30 s
    }

    @Test func ignoresInaccurateAndImpossiblePoints() {
        var r = recorder()
        r.add(point(0))
        r.add(point(1, accuracy: 50))
        r.add(GeoPoint(date: t0 + 20, latitude: 45.0045, longitude: 0, accuracy: 5))   // 500 m in 20 s
        r.add(point(2))
        #expect(abs(r.distance - 111.2) < 1)
        #expect(r.points.count == 2)
    }

    @Test func pauseStartsANewSegment() {
        var r = recorder()
        r.add(point(0)); r.add(point(1))
        r.pause(at: t0 + 15)
        r.add(point(5))                                              // ignored while paused
        r.resume(at: t0 + 75)
        r.add(point(10, at: 80)); r.add(point(11, at: 90))
        #expect(abs(r.distance - 111.2) < 1)
        #expect(r.segments.count == 2)
        #expect(r.movingTime(at: t0 + 90) == 30)
    }

    @Test func timeInZones() {
        var r = recorder()
        r.add(heartRate: 135, at: t0)        // zone 2
        r.add(heartRate: 150, at: t0 + 5)    // zone 3
        r.add(heartRate: 150, at: t0 + 60)   // gap capped at 10 s
        #expect(r.timeInZone == [2: 5, 3: 10])
        #expect(r.timeInTarget == 5)
        #expect(r.averageHeartRate == 145 && r.maxHeartRate == 150)
    }

    @Test func finishFreezesTime() {
        var r = recorder()
        r.finish(at: t0 + 600)
        #expect(r.state == .finished && r.end == t0 + 600)
        #expect(r.movingTime(at: t0 + 9999) == 600)
        r.add(point(1))
        #expect(r.points.isEmpty)
    }

    @Test func ignoresStaleFixes() {
        // Review finding: CoreLocation's cached first fix (home, 30 min old) added kilometers.
        var r = recorder()
        r.add(GeoPoint(date: t0 - 1800, latitude: 45.05, longitude: 0, accuracy: 10))
        r.add(point(0)); r.add(point(1))
        #expect(r.points.count == 2)
        #expect(abs(r.distance - 55.6) < 1)
    }

    @Test func ignoresFixesFromBeforeAResume() {
        var r = recorder()
        r.add(point(0))
        r.pause(at: t0 + 15)
        r.resume(at: t0 + 75)
        r.add(point(3, at: 70))                                      // delivered late, taken while paused
        r.add(point(4, at: 80))
        #expect(r.segments.last?.map(\.date) == [t0 + 80])
    }

    @Test func pausesAreKept() {
        var r = recorder()
        r.pause(at: t0 + 15)
        r.resume(at: t0 + 75)
        r.pause(at: t0 + 100)
        r.finish(at: t0 + 130)
        #expect(r.pauses == [DateInterval(start: t0 + 15, end: t0 + 75), DateInterval(start: t0 + 100, end: t0 + 130)])
    }

    @Test func ridesAllowFasterSpeeds() {
        // 0.0018 degrees (about 200 m) in 10 s = 20 m/s: too fast on foot, fine on a bike.
        func fast(_ activity: WorkoutActivity) -> ActivityRecorder {
            var r = ActivityRecorder(activity: activity, targetZone: nil, zones: zones, start: t0)
            r.add(GeoPoint(date: t0, latitude: 45, longitude: 0, accuracy: 5))
            r.add(GeoPoint(date: t0 + 10, latitude: 45.0018, longitude: 0, accuracy: 5))
            return r
        }
        #expect(fast(.running).points.count == 1)
        #expect(fast(.cycling).points.count == 2)
    }

    @Test func lastEventDate() {
        var r = recorder()
        #expect(r.lastEventDate == nil)
        r.add(point(1))
        r.add(heartRate: 140, at: t0 + 30)
        #expect(r.lastEventDate == t0 + 30)
    }

    @Test func recorderRoundTripsThroughJSON() throws {
        var r = recorder()
        for step in 0...3 { r.add(point(step)) }
        r.add(heartRate: 140, at: t0 + 3)
        r.pause(at: t0 + 40)
        let copy = try JSONDecoder().decode(ActivityRecorder.self, from: JSONEncoder().encode(r))
        #expect(copy == r)
    }
}

@MainActor
struct ActivityStoreTests {
    let store: RecordStore
    let t0 = utcDate(2026, 6, 16, 13, 30)

    init() throws {
        store = RecordStore(container: try RecordStore.container(inMemory: true))
    }

    private func finished(minutes: Double) -> ActivityRecorder {
        var r = ActivityRecorder(activity: .running, targetZone: 2, zones: HeartRateZones(max: 179, resting: 59), start: t0)
        r.finish(at: t0 + minutes * 60)
        return r
    }

    @Test func savesAndListsActivities() throws {
        let id = UUID()
        try store.save(finished(minutes: 20), id: id)
        let all = try store.activities(from: t0 - 3600, to: t0 + 3600)
        #expect(all.map(\.id) == [id])
        #expect(all.first?.recorder == finished(minutes: 20))
        #expect(try store.pendingActivities().count == 1)
        try store.markActivityExported(all)
        #expect(try store.pendingActivities().isEmpty)
        #expect(try store.activityIntervals(from: t0 - 3600, to: t0 + 3600) == [DateInterval(start: t0, end: t0 + 1200)])
    }

    @Test func savingTheSameActivityTwiceKeepsOne() throws {
        let id = UUID()
        #expect(try store.save(finished(minutes: 20), id: id))
        try store.markActivityExported(try store.pendingActivities())
        #expect(try !store.save(finished(minutes: 20), id: id))
        #expect(try store.pendingActivities().isEmpty)                 // not exported again
    }

    @Test func bandDistanceDuringAGpsActivityIsHeldBack() async throws {
        try store.save(finished(minutes: 20), id: UUID())             // 13:30-13:50
        let health = FakeHealth()
        let engine = SyncEngine(store: store, health: health, reader: HistoryReader(timeZone: utc), now: { utcDate(2026, 10, 2) })
        let channel = FakeChannel(respond: bandResponder([.activity: [bytes("52 00 00 26 06 16 13 33 58 5d 00 7a 3b 06 00 3c 21 00 00 00 00 00 00 00 00")]]))
        _ = try await engine.sync(over: channel, serial: "S")
        #expect(health.saved.contains { $0.metric == .steps })
        #expect(!health.saved.contains { $0.metric == .distance })
        // The run's own heart rate goes to Health; the band's for the same span must not.
        let spot = HistoryRecord(kind: .spotHR, raw: bytes("55 00 00 26 06 16 13 40 00 50"), timeZone: utc)!
        try store.insert([spot], serial: "S2")
        _ = try await engine.exportToHealth()
        #expect(!health.saved.contains { $0.metric == .heartRate })
        #expect(try store.pendingExport().isEmpty)                     // held-back samples are not retried
    }
}
