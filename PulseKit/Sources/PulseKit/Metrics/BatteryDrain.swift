import Foundation

/// Average battery use per day from readings, counting falling and flat stretches. Rises are
/// charging, and flat stretches at 100% are the band sitting full on the charger: both excluded.
public enum BatteryDrain {
    public static let minimumSpan: TimeInterval = 2 * 86400

    public static func perDay(_ readings: [BatteryReading]) -> Double? {
        let sorted = readings.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last,
              last.date.timeIntervalSince(first.date) >= minimumSpan else { return nil }
        var drop = 0.0
        var time = 0.0
        for (a, b) in zip(sorted, sorted.dropFirst()) where b.percent <= a.percent && !(a.percent == 100 && b.percent == 100) {
            drop += Double(a.percent - b.percent)
            time += b.date.timeIntervalSince(a.date)
        }
        guard time > 0 else { return nil }
        return drop / time * 86400
    }
}
