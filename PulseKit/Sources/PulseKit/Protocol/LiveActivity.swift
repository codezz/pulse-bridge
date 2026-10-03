import Foundation

/// Today's totals from the `09` real-time stream (layout: docs/protocol.md, "Live data").
public struct LiveActivity: Sendable, Equatable {
    public let steps: Int
    public let calories: Double
    public let distanceMeters: Int
    /// Raw band value; the unit (seconds or minutes) is unverified.
    public let activeTime: Int
    public let heartRate: Int?

    /// Nil for anything but a full `09` stream packet (the 16-byte command ack is not one).
    public init?(packet: Data) {
        let b = [UInt8](packet)
        guard b.count >= 28, b[0] == Opcode.realTimeActivity else { return nil }
        steps = littleEndian(b, at: 1, count: 4)
        calories = Double(littleEndian(b, at: 5, count: 4)) / 100
        distanceMeters = littleEndian(b, at: 9, count: 4) * 10
        activeTime = littleEndian(b, at: 13, count: 4)
        heartRate = b[27] > 0 ? Int(b[27]) : nil
    }
}
