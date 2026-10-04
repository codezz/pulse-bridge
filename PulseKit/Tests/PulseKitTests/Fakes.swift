import Foundation
@testable import PulseKit

/// Replays canned packets. `respond` returns the packets the band would send for a frame.
@MainActor
final class FakeChannel: CommandChannel {
    var sent: [Data] = []
    var respond: (Data) -> [Data]
    /// Throw `.notConnected` instead of delivering packet number `disconnectAfter + 1`.
    var disconnectAfter: Int?
    private(set) var queue: [Data] = []
    enum Event: Equatable { case send, packet, quiet }
    /// Timeout passed to the first `nextPacket` after each `send`.
    private(set) var firstWaits: [Duration] = []
    /// Every timeout passed to `nextPacket`, and the order of sends, packets and quiet periods.
    private(set) var waits: [Duration] = []
    private(set) var events: [Event] = []
    private var delivered = 0
    private var justSent = false

    init(respond: @escaping (Data) -> [Data] = { _ in [] }) {
        self.respond = respond
    }

    func send(_ frame: Data) async throws {
        sent.append(frame)
        queue += respond(frame)
        justSent = true
        events.append(.send)
    }

    func nextPacket(timeout: Duration) async throws -> Data? {
        if justSent { firstWaits.append(timeout); justSent = false }
        waits.append(timeout)
        guard !queue.isEmpty else { events.append(.quiet); return nil }
        events.append(.packet)
        if let limit = disconnectAfter, delivered >= limit { throw PulseError.notConnected }
        delivered += 1
        return queue.removeFirst()
    }
}

/// Spot heart-rate record at 2026-06-16 10:<minute>:00.
func spotHR(minute: Int, bpm: UInt8 = 70) -> Data {
    Data([0x55, 0x00, 0x00, 0x26, 0x06, 0x16, 0x10, BCD.byte(minute), 0x00, bpm])
}

@MainActor
final class FakeHealth: HealthWriter {
    var saved: [HealthSample] = []
    var denied: Set<HealthMetric> = []

    func requestAuthorization() async throws {}

    func save(_ samples: [HealthSample]) async throws -> Set<HealthMetric> {
        saved += samples.filter { !denied.contains($0.metric) }
        return denied.intersection(samples.map(\.metric))
    }
}

/// Suspends on the first send until `gate` is resumed; later sends return at once.
@MainActor
final class GatedChannel: CommandChannel {
    var gate: CheckedContinuation<Void, Never>?
    private var opened = false
    func send(_ frame: Data) async throws {
        guard !opened else { return }
        opened = true
        await withCheckedContinuation { gate = $0 }
    }
    func nextPacket(timeout: Duration) async throws -> Data? { nil }
}

/// Acks set-time and answers each history kind with its records plus the end marker.
/// Kinds in `silent` never answer.
func bandResponder(_ records: [HistoryKind: [Data]], silent: Set<HistoryKind> = []) -> (Data) -> [Data] {
    { frame in
        let b = [UInt8](frame)
        if b[0] == Opcode.setTime { return [Frame.make([Opcode.setTime, 0xF4])] }
        guard let kind = HistoryKind(rawValue: b[0]), !silent.contains(kind) else { return [] }
        if b[1] == HistoryMode.next.rawValue { return [] }
        return (records[kind] ?? []) + [Data([b[0], 0xFF])]
    }
}

/// A channel whose packets the test pushes while the code under test is reading.
@MainActor
final class ScriptedChannel: CommandChannel {
    private(set) var sent: [Data] = []
    private(set) var queue: [Data] = []
    private var waiter: CheckedContinuation<Data?, Error>?
    private var broken = false
    /// While true, `send` records the frame and then suspends until `releaseSends()`.
    var holdSends = false
    private var heldSends: [CheckedContinuation<Void, Never>] = []

    /// While true, `send` throws instead of recording.
    var failSends = false
    /// This many reads throw `busy`, as when another reader briefly holds the channel.
    var busyReads = 0

    func send(_ frame: Data) async throws {
        if failSends { throw PulseError.notConnected }
        sent.append(frame)
        if holdSends { await withCheckedContinuation { heldSends.append($0) } }
    }

    func releaseSends() {
        holdSends = false
        heldSends.forEach { $0.resume() }
        heldSends.removeAll()
    }

    func push(_ packet: Data) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: packet)
        } else {
            queue.append(packet)
        }
    }

    /// Simulates the band dropping the connection.
    func disconnect() {
        broken = true
        waiter?.resume(throwing: PulseError.notConnected)
        waiter = nil
    }

    func nextPacket(timeout: Duration) async throws -> Data? {
        if broken { throw PulseError.notConnected }
        if busyReads > 0 {
            busyReads -= 1
            throw PulseError.busy
        }
        if !queue.isEmpty { return queue.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if let waiter = self.waiter {
                    self.waiter = nil
                    waiter.resume(returning: nil)
                }
            }
        }
    }
}

@MainActor
final class TestClock {
    var now = utcDate(2026, 10, 2, 19, 0)
}

/// Polls until `condition` holds (or 2 s pass) while the code under test runs.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    let end = ContinuousClock.now + .seconds(2)
    while !condition() {
        if ContinuousClock.now > end { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
