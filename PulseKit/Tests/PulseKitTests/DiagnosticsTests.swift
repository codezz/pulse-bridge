import Foundation
import Testing
@testable import PulseKit

@MainActor
struct DiagnosticsTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString).log")
    let t0 = utcDate(2026, 10, 2, 22, 0)

    @Test func writesTimestampedLines() throws {
        let log = DiagnosticsLog(url: url, now: { self.t0 })
        log.note("sync started")
        log.packet(.sent, bytes("41 00 ff"))
        #expect(try String(contentsOf: url, encoding: .utf8) ==
            "2026-10-02T22:00:00.000Z note sync started\n2026-10-02T22:00:00.000Z sent 41 00 ff\n")
    }

    @Test func keepsOnlyTheNewestLinesWhenFull() throws {
        let log = DiagnosticsLog(url: url, maxBytes: 200, now: { self.t0 })
        for i in 0..<20 { log.note("line \(i)") }
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.utf8.count <= 200)
        #expect(text.hasSuffix("note line 19\n"))
        #expect(!text.contains("line 0\n"))
        #expect(text.hasPrefix("2026-10-02T22"))   // trimmed at a line start
    }

    @Test func survivesRelaunchAndClears() throws {
        DiagnosticsLog(url: url, now: { self.t0 }).note("first run")
        let again = DiagnosticsLog(url: url, now: { self.t0 })
        again.note("second run")
        #expect(try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").count == 3)
        again.clear()
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
    }

    @Test func recordingChannelLogsTrafficAndSkipsNoise() async throws {
        let log = DiagnosticsLog(url: url, now: { self.t0 })
        let band = FakeChannel { _ in [bytes("09 4a 00"), bytes("55 ff")] }
        let channel = RecordingChannel(band, log: log, skip: { $0.first == Opcode.realTimeActivity })
        try await channel.send(Frame.make([0x55]))
        _ = try await channel.nextPacket(timeout: .seconds(1))
        _ = try await channel.nextPacket(timeout: .seconds(1))
        _ = try await channel.nextPacket(timeout: .seconds(1))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("sent 55 00"))
        #expect(text.contains("received 55 ff"))
        #expect(!text.contains("09 4a"))
        #expect(text.contains("quiet after 1 s"))
    }

    @Test func pollingReadersCanSkipQuietNotes() async throws {
        let log = DiagnosticsLog(url: url, now: { self.t0 })
        let channel = RecordingChannel(FakeChannel(), log: log, logQuiet: false)
        _ = try await channel.nextPacket(timeout: .milliseconds(300))
        #expect(try String(contentsOf: url, encoding: .utf8).isEmpty)
        _ = try await RecordingChannel(FakeChannel(), log: log).nextPacket(timeout: .milliseconds(300))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("quiet after 300 ms"))
    }
}
