import Foundation
import SwiftData

/// A band record kept on the phone. The raw bytes are stored so later decoders (e.g. sleep) can reuse them.
@Model
public final class StoredRecord {
    #Index<StoredRecord>([\.kindRaw, \.start], [\.exported])

    @Attribute(.unique) public var id: String
    public var kindRaw: Int
    public var start: Date
    public var raw: Data
    /// True once written to Health, or never meant for it (local-only kind or before Health start).
    public var exported: Bool
    /// Bumped when the band sends changed bytes for a record still being filled.
    public var version: Int = 1

    init(id: String, record: HistoryRecord, healthStart: Date?) {
        self.id = id
        kindRaw = Int(record.kind.rawValue)
        start = record.start
        raw = record.raw
        exported = !record.goesToHealth(since: healthStart)
    }

    public var historyRecord: HistoryRecord? {
        guard let kind = HistoryKind(rawValue: UInt8(kindRaw)), raw.count == kind.recordSize else { return nil }
        return HistoryRecord(kind: kind, start: start, raw: raw)
    }
}

extension HistoryRecord {
    /// Health gets exportable kinds recorded at or after the Health start date.
    func goesToHealth(since healthStart: Date?) -> Bool {
        kind.exportsToHealth && start >= (healthStart ?? .distantPast)
    }
}
