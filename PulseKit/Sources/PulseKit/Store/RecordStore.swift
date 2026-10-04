import Foundation
import SwiftData

@MainActor
public final class RecordStore {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Same band timestamp within this many seconds of real time = the same record.
    static let sameRecordTolerance: TimeInterval = 30 * 60

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: StoredRecord.self, StoredActivity.self, StoredBatteryReading.self, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    /// A store in a specific file (the macOS test tool keeps its own database).
    public static func container(url: URL) throws -> ModelContainer {
        try ModelContainer(for: StoredRecord.self, StoredActivity.self, StoredBatteryReading.self, configurations: ModelConfiguration(url: url))
    }

    static let batteryInterval: TimeInterval = 15 * 60
    static let batteryKeep: TimeInterval = 90 * 86400

    /// At most one reading per 15 minutes: a newer value within that time replaces the last one (the
    /// value read right after connecting can be stale), keeping its time. Older than 90 days: dropped.
    public func recordBattery(_ percent: Int, at date: Date) throws {
        var latest = FetchDescriptor<StoredBatteryReading>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        latest.fetchLimit = 1
        if let last = try context.fetch(latest).first, date.timeIntervalSince(last.date) < Self.batteryInterval {
            last.percent = percent
            try context.save()
            return
        }
        let cutoff = date.addingTimeInterval(-Self.batteryKeep)
        try context.delete(model: StoredBatteryReading.self, where: #Predicate { $0.date < cutoff })
        context.insert(StoredBatteryReading(date: date, percent: percent))
        try context.save()
    }

    public func batteryReadings(since: Date) throws -> [BatteryReading] {
        try context.fetch(FetchDescriptor<StoredBatteryReading>(predicate: #Predicate { $0.date >= since },
                                                                sortBy: [SortDescriptor(\.date)]))
            .map { BatteryReading(date: $0.date, percent: $0.percent) }
    }

    /// The read cursor: newest stored record of a kind.
    public func latestStart(of kind: HistoryKind) throws -> Date? {
        let raw = Int(kind.rawValue)
        var descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.start
    }

    /// Stored records of the given kinds starting in `[from, to)`, oldest first.
    public func records(of kinds: [HistoryKind], from: Date, to: Date) throws -> [HistoryRecord] {
        let raws = kinds.map { Int($0.rawValue) }
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { raws.contains($0.kindRaw) && $0.start >= from && $0.start < to },
            sortBy: [SortDescriptor(\.start)])
        return try context.fetch(descriptor).compactMap(\.historyRecord)
    }

    /// Saves a finished activity once; returns false if this id is already stored (e.g. a recovery saved twice).
    @discardableResult
    public func save(_ recorder: ActivityRecorder, id: UUID) throws -> Bool {
        var existing = FetchDescriptor<StoredActivity>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        guard try context.fetchCount(existing) == 0 else { return false }
        context.insert(StoredActivity(id: id, recorder: recorder, data: try JSONEncoder().encode(recorder)))
        try context.save()
        return true
    }

    /// Recorded activities starting in `[from, to)`, newest first.
    public func activities(from: Date, to: Date) throws -> [StoredActivity] {
        try context.fetch(FetchDescriptor<StoredActivity>(
            predicate: #Predicate { $0.start >= from && $0.start < to }, sortBy: [SortDescriptor(\.start, order: .reverse)]))
    }

    public func pendingActivities() throws -> [StoredActivity] {
        try context.fetch(FetchDescriptor<StoredActivity>(predicate: #Predicate { $0.exported == false }))
    }

    public func markActivityExported(_ activities: [StoredActivity]) throws {
        activities.forEach { $0.exported = true }
        try context.save()
    }

    /// Time spans of recorded activities overlapping `[from, to)`.
    public func activityIntervals(from: Date, to: Date) throws -> [DateInterval] {
        try context.fetch(FetchDescriptor<StoredActivity>(predicate: #Predicate { $0.end > from && $0.start < to }))
            .map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
    }

    /// Saves records not stored yet and re-queues stored ones whose bytes changed
    /// (a block the band was still filling). Records before `healthStart` stay on the phone only.
    /// Returns how many were new.
    @discardableResult
    public func insert(_ records: [HistoryRecord], serial: String, healthStart: Date? = nil) throws -> Int {
        let ids = records.map { $0.id(serial: serial) }
        // A second record with the same band timestamp but another real time: the hour the band repeats
        // when the clock goes back (autumn, travelling west). It is stored under this alternate id.
        let alternates = zip(records, ids).map { "\($1)@\(Int($0.start.timeIntervalSince1970))" }
        let lookup = ids + alternates
        let stored = try context.fetch(FetchDescriptor<StoredRecord>(predicate: #Predicate { lookup.contains($0.id) }))
        var existing = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var added = 0
        for ((record, id), alternate) in zip(zip(records, ids), alternates) {
            guard let old = existing[id] else {
                let new = StoredRecord(id: id, record: record, healthStart: healthStart)
                context.insert(new)
                existing[id] = new
                added += 1
                continue
            }
            // Same record re-read (maybe in another clock offset): nothing to do.
            if old.historyRecord?.payload == record.payload { continue }
            let target: StoredRecord
            if abs(old.start.timeIntervalSince(record.start)) < Self.sameRecordTolerance {
                target = old                                     // a block the band was still filling
            } else if let repeated = existing[alternate] {
                guard repeated.historyRecord?.payload != record.payload else { continue }
                target = repeated
            } else {
                let new = StoredRecord(id: alternate, record: record, healthStart: healthStart)
                context.insert(new)
                existing[alternate] = new
                added += 1
                continue
            }
            target.raw = record.raw
            target.version += 1
            target.exported = !record.goesToHealth(since: healthStart)
        }
        try context.save()
        return added
    }

    public func pendingExport() throws -> [StoredRecord] {
        try context.fetch(FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.exported == false },
            sortBy: [SortDescriptor(\.start)]))
    }

    public func markExported(_ records: [StoredRecord]) throws {
        records.forEach { $0.exported = true }
        try context.save()
    }
}
