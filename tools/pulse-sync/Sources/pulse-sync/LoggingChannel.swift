import Foundation
import PulseKit

/// Wraps the real band channel and prints one summary line per command, plus a raw JSONL log.
@MainActor
final class LoggingChannel: CommandChannel {
    private struct Command {
        let frame: Data
        let sentAt: ContinuousClock.Instant
        var packets = 0
        var bytes = 0
        var firstPacket: Duration?
        var lastPacket: Duration?
    }

    private let base: any CommandChannel
    private let log: FileHandle
    private var current: Command?

    init(_ base: any CommandChannel, logURL: URL) throws {
        self.base = base
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        log = try FileHandle(forWritingTo: logURL)
    }

    func send(_ frame: Data) async throws {
        finish()
        current = Command(frame: frame, sentAt: .now)
        write(["type": "send", "hex": frame.hex(separator: " ")])
        try await base.send(frame)
    }

    func nextPacket(timeout: Duration) async throws -> Data? {
        let packet = try await base.nextPacket(timeout: timeout)
        if let packet, var command = current {
            let elapsed = ContinuousClock.now - command.sentAt
            command.packets += 1
            command.bytes += packet.count
            command.firstPacket = command.firstPacket ?? elapsed
            command.lastPacket = elapsed
            current = command
            write(["type": "notify", "hex": packet.hex(separator: " ")])
        } else if packet == nil {
            write(["type": "quiet", "timeout": "\(timeout)"])
        }
        return packet
    }

    /// Prints the summary of the command in flight.
    func finish() {
        guard let command = current else { return }
        current = nil
        let head = command.frame.prefix(2).hex(separator: " ")
        let first = command.firstPacket.map(Self.seconds) ?? "-"
        let last = command.lastPacket.map(Self.seconds) ?? "-"
        print("  -> \(head)  packets=\(command.packets) bytes=\(command.bytes) first=\(first) last=\(last)")
    }

    private func write(_ fields: [String: String]) {
        var line = fields
        line["t"] = ISO8601DateFormatter.string(from: .now, timeZone: .current, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
            log.write(data + Data("\n".utf8))
        }
    }

    private static func seconds(_ d: Duration) -> String {
        String(format: "%.2fs", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }
}
