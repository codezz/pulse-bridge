import Foundation

public struct HistoryResult: Sendable, Equatable {
    public var records: [HistoryRecord] = []
    /// Records that failed to parse (bad size or timestamp).
    public var dropped = 0
}

/// Reads one history kind, newest first, stopping at the first record already known.
@MainActor
public struct HistoryReader {
    /// The band sends at most 50 notifications per page, then waits for a "next" command.
    public static let packetsPerPage = 50
    /// Records dated before this come from a reset band clock.
    public static let plausibleSince = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01

    public var timeZone: TimeZone
    /// The band can pause about 3 s inside a page and takes up to about 2.5 s to start one.
    public var packetTimeout: Duration = .seconds(5)
    public var endMarkerGrace: Duration = .milliseconds(300)

    /// Auto-updating so a long-running app follows the phone across time zones.
    public init(timeZone: TimeZone = .autoupdatingCurrent) {
        self.timeZone = timeZone
    }

    /// A page ends at the `<op> ff` marker or after 50 packets (then the next page is requested).
    /// Silence never ends a page early: it fails the read, so the cursor can't skip data.
    public func read(_ kind: HistoryKind, newerThan cursor: Date?, over channel: some CommandChannel) async throws -> HistoryResult {
        var result = HistoryResult()
        var assembler = ResponseAssembler(kind: kind)
        var mode = HistoryMode.newest
        while true {
            assembler.startPage()
            try await channel.send(Command.history(kind, mode: mode))
            while assembler.packetCount < Self.packetsPerPage {
                guard let packet = try await channel.nextPacket(timeout: packetTimeout) else {
                    throw PulseError.noResponse(kind.rawValue)
                }
                // Button events can arrive anywhere; leftovers from the previous command never
                // start with our opcode.
                if Frame.isDeviceEvent(packet) { continue }
                if assembler.isAtRecordBoundary && packet.first != kind.rawValue { continue }
                for bytes in assembler.append(packet) {
                    guard let record = HistoryRecord(kind: kind, raw: Data(bytes), timeZone: timeZone) else {
                        result.dropped += 1
                        continue
                    }
                    // A band clock reset stamps records around 2000: unusable, but no reason to stop.
                    guard record.start >= Self.plausibleSince else {
                        result.dropped += 1
                        continue
                    }
                    if let cursor, record.start <= cursor {
                        try await drain(channel)
                        return result
                    }
                    result.records.append(record)
                }
                // The band sends whole records per packet, so two leftover bytes can only be the marker.
                if assembler.endMarkerPending { return result }
            }
            mode = .next
        }
    }

    /// Swallows the rest of a page we stopped reading, so it can't leak into the next command.
    private func drain(_ channel: some CommandChannel) async throws {
        while try await channel.nextPacket(timeout: endMarkerGrace) != nil {}
    }
}
