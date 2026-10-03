import Foundation
import Testing
@testable import PulseKit

@MainActor
struct LiveFeedTests {
    let clock = TestClock()
    let channel = ScriptedChannel()
    let feed: LiveFeed
    let activityPacket = bytes("09 4a 00 00 00 51 10 02 00 05 00 00 00 26 00 00 00 00 00 00 00 00 00 00 00 00 00 3e 47 00")
    let hrvResult = Frame.make([0x28, 0x01, 0x57, 0x00, 0x20, 0x39, 0x78, 0x4b, 0xe9])
    let finished = bytes("28 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 27")

    init() {
        let clock = clock
        feed = LiveFeed(now: { clock.now })
        feed.pollTimeout = .milliseconds(10)
    }

    @Test func startEnablesTheStreamAndParsesActivity() async throws {
        try await feed.start(over: channel)
        #expect(channel.sent == [Command.realTimeActivity(true)])
        channel.push(activityPacket)
        #expect(await eventually { feed.activity != nil })
        #expect(feed.activity?.steps == 74)
        #expect(feed.lastActivityAt == clock.now)
    }

    @Test func stopReturnsOnlyAfterTheLoopStoppedReading() async throws {
        try await feed.start(over: channel)
        await feed.stop()
        #expect(channel.sent.last == Command.realTimeActivity(false))
        #expect(!feed.isRunning)
        channel.push(activityPacket) // must stay for the next reader (the sync)
        try await Task.sleep(for: .milliseconds(50))
        #expect(channel.queue.count == 1)
        #expect(feed.activity == nil)
    }

    @Test func hrvMeasurementFinishesWithItsLastValues() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.hrv)
        #expect(channel.sent.last == Command.measurement(.hrv, start: true))
        channel.push(Frame.make([0x28, 0x01, 0x3c]))
        #expect(await eventually { if case .running(.hrv, let v?, _) = feed.measurement { v.heartRate == 60 } else { false } })
        channel.push(hrvResult)
        channel.push(finished)
        let expected = MeasurementValues(kind: .hrv, heartRate: 87, hrv: 32, stress: 57, systolic: 120, diastolic: 75)
        #expect(await eventually { feed.measurement == .finished(expected) })
        #expect(!feed.isMeasuring)
    }

    @Test func hrvFinishesOnItsResultWithoutAnEndMarker() async throws {
        // Real band (log 2026-10-02 19:48): the HRV result repeats a few times, no `28 ff` follows.
        var ended = 0
        feed.onMeasurementEnded = { _ in ended += 1 }
        try await feed.start(over: channel)
        try await feed.measure(.hrv)
        channel.push(Frame.make([0x28, 0x01, 0x58]))
        channel.push(hrvResult)
        channel.push(hrvResult)
        let expected = MeasurementValues(kind: .hrv, heartRate: 87, hrv: 32, stress: 57, systolic: 120, diastolic: 75)
        #expect(await eventually { feed.measurement == .finished(expected) })
        try await Task.sleep(for: .milliseconds(50))
        #expect(ended == 1)
    }

    @Test func measurementWithoutAReadingFails() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.heartRate)
        channel.push(Frame.make([0x28, 0x02, 0x00]))
        channel.push(finished)
        #expect(await eventually { feed.measurement == .failed(.heartRate) })
    }

    @Test func measurementTimesOut() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.heartRate)
        clock.now = clock.now.addingTimeInterval(121)
        #expect(await eventually { feed.measurement == .failed(.heartRate) })
        #expect(channel.sent.last == Command.measurement(.heartRate, start: false))
    }

    @Test func cancelStopsTheBandMeasurement() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.hrv)
        await feed.cancelMeasurement()
        #expect(channel.sent.last == Command.measurement(.hrv, start: false))
        #expect(feed.measurement == .idle)
    }

    @Test func stopDuringMeasurementStopsTheBand() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.hrv)
        await feed.stop()
        #expect(channel.sent.suffix(2) == [Command.measurement(.hrv, start: false), Command.realTimeActivity(false)])
        #expect(feed.measurement == .interrupted(.hrv))
    }

    @Test func disconnectFailsTheRunningMeasurement() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.hrv)
        channel.disconnect()
        #expect(await eventually { !feed.isRunning })
        #expect(feed.measurement == .interrupted(.hrv))
    }

    @Test func restartsAfterADisconnect() async throws {
        try await feed.start(over: channel)
        channel.disconnect()
        #expect(await eventually { !feed.isRunning })
        let fresh = ScriptedChannel()
        try await feed.start(over: fresh)
        #expect(fresh.sent == [Command.realTimeActivity(true)])
        #expect(feed.isRunning)
    }

    @Test func stopWaitsForAStartThatIsStillSending() async throws {
        // Review finding: stop() during start()'s first await used to return at once, and the
        // loop started reading afterwards, alongside the sync.
        channel.holdSends = true
        let starting = Task { try await feed.start(over: channel) }
        #expect(await eventually { channel.sent.count == 1 })
        let stopping = Task { await feed.stop() }
        try await Task.sleep(for: .milliseconds(30))
        channel.releaseSends()
        await stopping.value
        _ = try? await starting.value
        #expect(channel.sent == [Command.realTimeActivity(true), Command.realTimeActivity(false)])
        #expect(!feed.isRunning)
        channel.push(activityPacket)
        try await Task.sleep(for: .milliseconds(50))
        #expect(channel.queue.count == 1)
    }

    @Test func secondStartWhileStartingIsIgnored() async throws {
        channel.holdSends = true
        let first = Task { try await feed.start(over: channel) }
        #expect(await eventually { channel.sent.count == 1 })
        let second = Task { try await feed.start(over: channel) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(channel.sent.count == 1)
        channel.releaseSends()
        _ = try? await first.value
        _ = try? await second.value
        #expect(channel.sent == [Command.realTimeActivity(true)])
    }

    @Test func failedStartCommandLeavesNoMeasurement() async throws {
        try await feed.start(over: channel)
        channel.failSends = true
        await #expect(throws: PulseError.notConnected) { try await feed.measure(.hrv) }
        #expect(feed.measurement == .idle)
    }

    @Test func reportsWhenAMeasurementEnds() async throws {
        var ended: [LiveFeed.MeasurementState] = []
        feed.onMeasurementEnded = { ended.append($0) }
        try await feed.start(over: channel)
        try await feed.measure(.heartRate)
        channel.push(Frame.make([0x28, 0x02, 0x48]))
        channel.push(finished)
        #expect(await eventually { ended.count == 1 })
        #expect(ended == [.finished(MeasurementValues(kind: .heartRate, heartRate: 72, hrv: 0, stress: 0, systolic: 0, diastolic: 0))])
        try await feed.measure(.hrv)
        await feed.cancelMeasurement()
        #expect(ended.count == 2)
    }

    @Test func ignoresStrayPackets() async throws {
        try await feed.start(over: channel)
        try await feed.measure(.heartRate)
        channel.push(bytes("55 00 00 26 10 02 19 18 20 3e"))                   // late history page
        channel.push(bytes("16 07 01 00 00 00 00 00 00 00 00 00 00 00 00 1e")) // button event
        channel.push(hrvResult)                                                 // other measurement kind
        channel.push(activityPacket)
        #expect(await eventually { feed.activity != nil })
        #expect(feed.measurement == .running(.heartRate, latest: nil, startedAt: clock.now))
    }

    @Test func measuringNeedsARunningFeed() async throws {
        try await feed.measure(.hrv)
        #expect(feed.measurement == .idle)
        #expect(channel.sent.isEmpty)
    }

    @Test func stopWhileAMeasurementIsStartingLeavesNothingRunning() async throws {
        try await feed.start(over: channel)
        channel.holdSends = true
        let measuring = Task { try await feed.measure(.hrv) }
        #expect(await eventually { channel.sent.last == Command.measurement(.hrv, start: true) })
        let stopping = Task { await feed.stop() }
        try await Task.sleep(for: .milliseconds(30))
        channel.releaseSends()
        await stopping.value
        _ = try? await measuring.value
        #expect(!feed.isMeasuring)
        #expect(channel.sent.last == Command.measurement(.hrv, start: false) || channel.sent.contains(Command.measurement(.hrv, start: false)))
    }
}
