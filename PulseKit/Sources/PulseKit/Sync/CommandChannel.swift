import Foundation

/// Transport to the band's FFF6 (write) / FFF7 (notify) pair.
@MainActor
public protocol CommandChannel: AnyObject {
    func send(_ frame: Data) async throws
    /// The next FFF7 notification, or nil if none arrives within `timeout`.
    func nextPacket(timeout: Duration) async throws -> Data?
}

public enum PulseError: Error, Equatable, LocalizedError {
    case notConnected
    case noResponse(UInt8)
    case busy

    public var errorDescription: String? {
        switch self {
        case .notConnected: L("The band disconnected.")
        case .noResponse(let op): L("The band did not answer command \(String(format: "0x%02X", op)).")
        case .busy: L("A sync is already running.")
        }
    }
}
