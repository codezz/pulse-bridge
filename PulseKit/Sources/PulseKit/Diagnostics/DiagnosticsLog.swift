import Foundation

/// A small text log of band traffic and sync events, kept in one file on the phone for bug reports.
/// When the file grows past `maxBytes`, the oldest half is dropped (at a line start).
@MainActor
public final class DiagnosticsLog {
    public enum Direction: String, Sendable { case sent, received }

    public let url: URL
    private let maxBytes: Int
    private let now: () -> Date
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(url: URL, maxBytes: Int = 1_000_000, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.maxBytes = maxBytes
        self.now = now
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    public func note(_ text: String) { append("note \(text)") }

    public func packet(_ direction: Direction, _ data: Data) {
        append("\(direction.rawValue) \(data.hex(separator: " "))")
    }

    public func clear() {
        try? Data().write(to: url)
    }

    private func append(_ line: String) {
        let entry = Data("\(formatter.string(from: now())) \(line)\n".utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if Int(size) + entry.count > maxBytes {
            try? handle.close()
            trim(adding: entry)
            return
        }
        try? handle.write(contentsOf: entry)
    }

    /// Keeps about the newest half of the allowed size, starting at a line, plus the new entry.
    private func trim(adding entry: Data) {
        guard let current = try? Data(contentsOf: url) else { return }
        let keep = max(0, maxBytes / 2 - entry.count)
        var tail = current.suffix(keep)
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) { tail = tail[(newline + 1)...] }
        try? (Data(tail) + entry).write(to: url)
    }
}

/// Passes a command channel through while writing everything it sends and receives to a log.
@MainActor
public final class RecordingChannel: CommandChannel {
    private let base: any CommandChannel
    private let log: DiagnosticsLog
    private let skip: (Data) -> Bool
    private let logQuiet: Bool

    /// `skip`: received packets not worth logging (e.g. the once-per-second live activity stream).
    /// `logQuiet`: false for readers that poll, like the live feed.
    public init(_ base: any CommandChannel, log: DiagnosticsLog, skip: @escaping (Data) -> Bool = { _ in false },
                logQuiet: Bool = true) {
        self.base = base
        self.log = log
        self.skip = skip
        self.logQuiet = logQuiet
    }

    public func send(_ frame: Data) async throws {
        log.packet(.sent, frame)
        do {
            try await base.send(frame)
        } catch {
            log.note("send failed: \(logText(error))")
            throw error
        }
    }

    public func nextPacket(timeout: Duration) async throws -> Data? {
        do {
            let packet = try await base.nextPacket(timeout: timeout)
            if let packet {
                if !skip(packet) { log.packet(.received, packet) }
            } else if logQuiet {
                let ms = timeout.components.seconds * 1000 + timeout.components.attoseconds / 1_000_000_000_000_000
                log.note(ms >= 1000 && ms % 1000 == 0 ? "quiet after \(ms / 1000) s" : "quiet after \(ms) ms")
            }
            return packet
        } catch {
            log.note("read failed: \(logText(error))")
            throw error
        }
    }
}

/// Errors for the diagnostics log: our own errors by case name (`noResponse(18)`), never their
/// translated description; system errors as iOS describes them (domain and code included).
public func logText(_ error: Error) -> String { String(describing: error) }
