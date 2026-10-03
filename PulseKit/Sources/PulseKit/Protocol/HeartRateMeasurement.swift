import Foundation

/// Standard Bluetooth Heart Rate Measurement (0x2A37).
public enum HeartRateMeasurement {
    public static func bpm(from data: Data) -> Int? {
        let b = [UInt8](data)
        guard let flags = b.first else { return nil }
        if flags & 0x01 == 0 { return b.count >= 2 ? Int(b[1]) : nil }
        return b.count >= 3 ? Int(b[1]) | Int(b[2]) << 8 : nil
    }
}
