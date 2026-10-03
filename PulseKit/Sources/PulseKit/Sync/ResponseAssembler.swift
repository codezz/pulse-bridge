import Foundation

/// Cuts a history response stream into fixed-size records. Records may span BLE packets.
public struct ResponseAssembler {
    public let kind: HistoryKind
    public private(set) var packetCount = 0
    private var buffer: [UInt8] = []

    public init(kind: HistoryKind) {
        self.kind = kind
    }

    /// Adds one notification and returns every record it completed.
    public mutating func append(_ packet: Data) -> [[UInt8]] {
        packetCount += 1
        buffer += packet
        var records: [[UInt8]] = []
        while buffer.count >= kind.recordSize {
            records.append(Array(buffer.prefix(kind.recordSize)))
            buffer.removeFirst(kind.recordSize)
        }
        return records
    }

    /// Nothing buffered: the next packet must start a new record (the band sends whole records per packet).
    public var isAtRecordBoundary: Bool { buffer.isEmpty }

    /// The leftover bytes are exactly `<op> ff`, the band's end-of-data marker.
    public var endMarkerPending: Bool { buffer == [kind.rawValue, 0xFF] }

    public mutating func startPage() {
        packetCount = 0
    }
}
