import Foundation

/// JStyle command frame: 15 payload bytes (zero padded) plus a sum checksum.
public enum Frame {
    public static let length = 16

    public static func make(_ bytes: [UInt8]) -> Data {
        precondition(bytes.count <= length - 1, "payload longer than 15 bytes")
        precondition(!Opcode.forbidden.contains(bytes.first ?? 0), "refusing to build a destructive command")
        precondition(!isDelete(bytes), "refusing to build a delete command")
        var body = bytes + [UInt8](repeating: 0, count: length - 1 - bytes.count)
        body.append(checksum(body))
        return Data(body)
    }

    /// Mode 99 deletes: every history read, the alarm read `57` (JStyle deleteAllClock) and the
    /// temperature reads. Workouts (`5C`) also delete with 09, so history reads refuse 09 too (as the
    /// probe does). Never built, whatever calls `make`.
    static let historyOpcodes: Set<UInt8> = Set(HistoryKind.allCases.map(\.rawValue)).union([0x60, 0x62])
    static let deleteCapable: Set<UInt8> = historyOpcodes.union([0x57])

    static func isDelete(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 1 else { return false }
        return (bytes[1] == 0x99 && deleteCapable.contains(bytes[0])) || (bytes[1] == 0x09 && historyOpcodes.contains(bytes[0]))
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
