import Foundation

/// One raw history record as sent by the band, plus its parsed start time.
public struct HistoryRecord: Sendable, Equatable {
    public let kind: HistoryKind
    public let start: Date
    public let raw: Data

    public init(kind: HistoryKind, start: Date, raw: Data) {
        self.kind = kind
        self.start = start
        self.raw = raw
    }

    /// Nil when the size, opcode or BCD timestamp is invalid.
    public init?(kind: HistoryKind, raw: Data, timeZone: TimeZone) {
        let b = [UInt8](raw)
        guard b.count == kind.recordSize, b.first == kind.rawValue,
              let start = BCD.date(b[kind.timestampRange], in: timeZone) else { return nil }
        self.init(kind: kind, start: start, raw: Data(b))
    }

    /// The bytes after the opcode and the band's record index (which shifts as new records arrive).
    public var payload: Data { raw.dropFirst(kind == .dailyTotals ? 2 : 3) }

    public var reading: BandReading { BandReading(kind: kind, bytes: [UInt8](raw)) }
}
