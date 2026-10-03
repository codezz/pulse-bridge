import Foundation

/// JStyle command frame: 15 payload bytes (zero padded) plus a sum checksum.
public enum Frame {
    public static let length = 16

    public static func make(_ bytes: [UInt8]) -> Data {
        precondition(bytes.count <= length - 1, "payload longer than 15 bytes")
        precondition(!Opcode.forbidden.contains(bytes.first ?? 0), "refusing to build a destructive command")
        var body = bytes + [UInt8](repeating: 0, count: length - 1 - bytes.count)
        body.append(checksum(body))
        return Data(body)
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        UInt8(truncatingIfNeeded: bytes.reduce(0) { $0 + Int($1) })
    }

    public static func isValid(_ frame: Data) -> Bool {
        frame.count == length && checksum(frame.prefix(length - 1)) == frame.last
    }

    /// Unsolicited button / photo-mode notifications (`16 xx yy ...`), not data.
    public static func isDeviceEvent(_ packet: Data) -> Bool {
        packet.first == 0x16 && isValid(packet)
    }
}
