import Foundation

extension Sequence where Element == UInt8 {
    /// Lowercase hex: "5101", or "51 01" with a space separator.
    public func hex(separator: String = "") -> String { map { String(format: "%02x", $0) }.joined(separator: separator) }
}

/// Unsigned little-endian integer of `count` bytes starting at `offset`.
func littleEndian(_ bytes: [UInt8], at offset: Int, count: Int) -> Int {
    bytes[offset..<offset + count].reversed().reduce(0) { $0 << 8 | Int($1) }
}
